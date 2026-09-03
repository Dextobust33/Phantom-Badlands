# Phantom Badlands — Master Backlog

**The single ordered to-do list.** Keep it current: when work finishes, move it to *Recently
shipped*; when a new direction is agreed, add it in the position its dependencies allow.

Ordering rule: **each item is placed so its inputs are settled first** — measurement before
tuning, data model before UI, combat numbers before anything sized against them. Working out of
order is what forces revisits.

> Detailed design and history live in `docs/design/` and in the assistant project memory.
> This file is the ordering and the status.

---

## ⚑ v0.9.741 SHIPPED — the balance day reached players (2026-09-03)

The 103 commits of 2026-09-02 are live: **client, launcher (both platforms) and server**,
under tag `v0.9.741`. Runtime was byte-identical to r1 (sha256 compared, not assumed), so
launcher users pulled a **14.7 MB content-only update** rather than 38 MB of runtime.

Shipped: the reference-player monster model at every level, apex species, role calibration,
the regeneration cap, the Forcefield anchor, companion durability and scaling, server-authoritative
ability costs, the mage kit re-pricing, the escape ratio fix, the per-encounter flock budget, and
the solo playback fix.

**Found while writing the changelog:** the apex feature was only half built. `is_apex` was
stamped on the monster with the comment *"so the client can mark one in the UI"* — and nothing
ever read it. The entire premise of apex species is that a player learns which ones to fear,
which cannot happen if the game never says which they are. Now carried through the combat state
and rendered as a red **☠ [APEX]** on the enemy health bar, stacking with ELITE rather than
replacing it, plus a help page section and a searchable help topic.

**Release-process notes worth keeping:**
- The `--editor --quit` recompile was done on the main project AND `launcher/` (separate cache)
- Build freshness was verified **by running the packaged exe** with a temp `[BUILDVERIFY]` print,
  as the rule requires. It reported `shared_apex_species=false` on the first pass — which was
  **the probe being wrong** (it named `get_combat_state`, a method that does not exist), not a
  stale build. Corrected probe confirmed client var, `MonsterDatabase.is_apex_species("Hydra")`
  and `CombatManager.FORCEFIELD_SHARE_OF_BAR=0.25` all live in the pck. Five instrument defects
  yesterday, one more today: **check the instrument first** applies to the release process too
- The reference curve is a `.json`; confirmed it loads in production by the ABSENCE of the
  fail-loud `push_error` in the deployed server's journal
- Nobody was connected at swap time (checked `ss` for established connections on 9080), so no
  in-game countdown was needed

**Known-open at ship time, and accepted:**
- Post-combat HP staleness — HP appears to drop BEFORE combat ends and the end-of-fight number
  is the stale one. Needs the HP ledger (instrument `process_monster_turn`), not a fourth guess
- Buff effects (Forcefield) take a beat to appear on the HP bar — same playback-gating family
- High-level fight LENGTH still swings; danger is calibrated, turns are not
- Boss win rate 18-46% — **a user DECISION, not a defect**: *"I'm okay with the bosses currently
  as I think companions and gear will make up the difference"*
- **Forcefield's 3-6x nerf wants a feel check in live play.** It was immunity before, so the
  direction is not in doubt, but 0.25x of the bar is an anchor picked by measurement, not by feel

---

## ⚑ MEASUREMENT DISCIPLINE — five instrument defects found in ONE day

Every one of these produced confident, wrong numbers, and several were reported to the user as
fact before being caught. Read this before trusting any historical figure in this file.

1. **Win counted twice** — the same `if` written twice in a row in `_fight_stats_at`. Every win
   rate that function ever printed was **2x the truth**
2. **`refcal` printed the pass BEFORE the value it wrote** — the table described a state one
   correction out of date
3. **Smoothing/clamping run AFTER the per-anchor print loop** — so the printed table described
   numbers that no longer existed by the time the file was written
4. **`refcal` silently wiped `rolecal`'s output** — it wrote only `anchors`, so a measured and
   reported boss danger fix was destroyed by the next calibration run with no warning
5. **Victory cost measured BEFORE post-defeat effects** — a flock that took the player to 1 HP
   logged as costing **0%** of the bar. Mine, written an hour earlier

**The rule that came out of it:** when the player's account disagrees with an instrument, check
the instrument first. In this session the player was right every single time — the missing
Forcefield shield, the one-shot companion, the vanished HP bar, the unwinnable regenerator, and
the 1 HP demon flock were all real, and in several cases the tooling actively denied them.

**The corollary that cost the most time:** a simulator cannot find a defect that depends on
playing well. Forcefield granting effective immunity was invisible to every audit because the
sim's mage AI does not maintain it. One sentence from the player — *"as long as I maintain it I
don't really get hurt"* — found what a day of calibration could not.

---

## In progress

**Item 6 (progression & difficulty curve) is the active arc.** Items 1-5 are done. On 2026-09-02
item 6 was split — it had grown to 21 open tasks covering two different jobs — into:
**6** the monster model and difficulty curve, **6b** companion power, **6c** class balance
(blocked, see below), **6d** risk/reward incentives.

### ✅ Sequencing: the unshipped balance body is now SHIPPED (v0.9.741, 2026-09-03)

This section used to warn that four significant balance changes sat in the tree, sim-validated
and unplayed. They are live as of v0.9.741 — the reference-player monster model, the role
targets, the escape fix, and the per-encounter flock budget. The player-post suppression floor
is the one deliberate exception: it remains behind `PLAYER_POST_TIER_FLOOR_ENABLED = false`
until 12b (the Phantom) gives a new character an on-ramp, and should be flipped in that same
change.

The sequencing consequence that still stands: **6c (class balance) was blocked because every
class number on record had been measured against the OLD monster model.** That re-measurement
is DONE (see 6c) — so 6c is unblocked, and its figures are the ones to trust.

**Status 2026-09-02:** (a) re-measurement DONE — see 6c. (b) **Playtest DONE and passed.**
A live L5 session confirmed the model on screen: flocks are survivable again after the
per-encounter danger fix (the same fight killed the character before it), an empowered
Broodcalling Orc read as a longer fight as designed, and combat timing now tracks the log.
User verdict: "seemed good from what I seen."

Three real bugs were found only by playing it, none of which the simulator can see:
- **Solo never got the party playback pass** — the gate was co-op-only, so in solo every
  result landed on message arrival while the text was still draining
- **The companion HP bar DISCARDED updates instead of deferring them** — the log said
  "knocked out" while the card still read 24/65
- Two harness faults that both presented as "my character is gone": a stale second server
  (the guard matched truncated `tasklist` output), and a rebuilt character that was never
  re-registered on the account after permadeath cleared its slot

**Next (as of 2026-09-03, post-release):** the measured-defect half of **6b** shipped in
v0.9.741 — companion HP by aggro, and damage/defense/resource-regen unflattened. What remains
under 6b is the *design* question (what a companion is FOR), which gates 12b, the Phantom loop.

So the live choice for the next session is between:
1. **A feel playtest of v0.9.741** — the largest balance change the game has had, and the one
   number picked by measurement rather than feel is Forcefield's 3-6x nerf. Cheap, and the last
   playtest found three bugs no simulator could see
2. **6c class balance** — now unblocked, with the mage roster the clearest remaining outlier
3. **6b's design half** — what a companion is for, which unblocks the 12b Phantom arc

Ask the owner rather than assuming; (1) is the cheapest and most likely to change what (2) and
(3) should say.

### What this session proved about trusting measurements

Item 5 found four modelling bugs in the simulator, each of which produced a confident, wrong
balance conclusion, and **three conclusions were reversed by verification alone** — including
two that had already been written up. Later work added more of the same: an "Exploit hits for
46000% of a health bar" reading that was a harness artifact, a "1 fight per level" XP reading
caused by the sim being unable to observe XP grants at all, and an "optimal strategy is to fight
things you lose to" headline that came from pricing a permadeath loss at zero.

**Check what a number is actually measuring before believing it, and re-check it before acting
on it.** Every finding in this file states how it was measured for that reason.

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

- [x] **Anchor monster stats to a reference player — BUILT 2026-09-02, behind `USE_REFERENCE_MODEL`
      in `monster_database.gd`.** Monster magnitude no longer comes from each species'
      hand-authored `base_level` run through an asymmetric up/down scale. It comes from a
      calibrated curve of what a real player at that level can actually do.

      **It is SELF-CALIBRATING, and that turned out to be the essential design decision.** The
      analytic route — measure player damage-per-turn, set `monster.hp = dpt × target_turns` —
      does not converge, because it is self-referential: a player bursts with abilities and then
      runs dry, so damage-per-turn depends on how long the fight lasts, which is exactly the
      number being set. Two failures made that concrete:
      - Averaging player output over a 12-turn window while designing 5-turn fights produced
        fights **2x too long at L1 and 16x too long at L5000** — a level-dependent error, because
        high-level fights ran longest and amortised the opening burst furthest
      - Matching the window to the target instead made **percentage-of-max-HP abilities blow up**
        against the oversized probe dummy (measured player damage-per-turn at L10000 leapt from
        1.9M to 39M)

      So the model stops predicting the fixed point and **finds** it: set stats, run real fights,
      correct toward target, repeat. It converges in 2-3 passes and is robust to every subtlety
      that broke the analytic version — ability rotations, resource drain, percentage damage,
      mitigation, monster abilities — because it never models any of them, only the outcome they
      jointly produce.

      **Results.** Same-level normal fights now land at 3.4-6.4 turns against a target of 5, with
      the player spending 25-66% of their health bar (target 40%) and winning 50-83%. And the
      structural defects are gone:

      | | before | after |
      |---|---|---|
      | median monster HP L2000→L2500 | **6.7x collapse** | strictly monotonic |
      | same-level HP variance | **85x** | **2-3x** (designed band) |
      | difficulty at tier boundaries | collapses every band | no discontinuity |

      **What it preserves.** Only magnitude is anchored. Species keep their abilities
      (multi_strike, regeneration, armored, ethereal…), their variants, glass_cannon, the
      elite/boss multipliers and XP — all still ride on top. Species also keep a bounded stat
      SHAPE derived from their own base-stat *ratios within their tier*, so a Hydra is still
      beefier than a Goblin, inside a designed ~2x band instead of an emergent 85x.

      **Difficulty is now an explicit knob**, which was the original goal and was previously not
      expressible anywhere: `TARGET_TURNS_NORMAL`, `DANGER_NORMAL`, and
      `PROGRESSION_DANGER_SLOPE` (danger × (1 + slope·log10(level)) — L1 ×1.00, L10000 ×1.24), so
      "the game gets harder as you progress" is a number someone chose rather than an accident of
      54 stat blocks.

      Sim audits: `-- refcurve` (player curve), `-- refcal` (calibrate against real fights),
      `-- refval` (validate), `-- selection` (sawtooth + variance regression test).

- [x] **Elite / boss / variant re-tuned against the corrected baseline (2026-09-02).** They had
      been sized against the old, too-weak baseline and inflated to compensate (Champion HP was
      raised 1.5 -> 3.5 in v0.9.700). Stacked on a correct baseline they made elites unwinnable
      — **0% win at L1**. Roles now state a target fight length and cost and the multipliers are
      derived: `hp_mult = turns_role/turns_normal`, `str_mult = (danger_role/danger_normal) *
      (turns_normal/turns_role)`. The strength term is the one that is easy to get wrong by
      hand and is why the old numbers compounded: damage taken is strength x turns, so making a
      monster tankier **already** makes it more dangerous — the old x3.5 HP with x1.3 STR came
      to ~4.5x a normal fight's cost rather than the intended 1.75x. `ROLE_TARGETS`: normal
      5t/40%, empowered 7t/55%, elite 9t/70%, boss 14t/85%. **Measured after: elites 46-80% win
      (was 0%), bosses 33-83%.** The sim reads `role_multipliers()` from the game rather than
      mirroring constants, so the two cannot drift apart again. Regression test: `-- roles`

**XP economy — measured 2026-09-02 (`-- xp`). Headline: the XP curve is HEALTHY. The
problem is what it incentivises.**

Fights needed to gain one level, same-level monsters, across the whole range:

| Level | XP needed | normal | empowered | elite | boss |
|-------|-----------|--------|-----------|-------|------|
| L1 | 230 | 42 | 45 | 60 | 51 |
| L50 | 285,512 | 39 | 54 | 61 | 70 |
| L1000 | 199,491,766 | 31 | 33 | 34 | 37 |
| L5000 | 6,869,024,800 | 34 | 36 | 38 | 49 |

**30-70 fights per level, flat from L1 to L5000.** That is close to the documented ~45
target and, more importantly, it does not drift with level. XP scaling needs no work.

**But the level-gap incentive is inverted, and permadeath makes it dangerous.** XP per
fight against monsters at a multiple of the player's level (losses counted as zero XP):

| Player | monster | win% | XP/fight | fights/level |
|--------|---------|------|----------|--------------|
| L50 | x0.25 | 91% | 222 | **1285** |
| L50 | x0.50 | 100% | 1,056 | 270 |
| L50 | x1.00 | 75% | 7,808 | 37 |
| L50 | x2.00 | 8% | 10,094 | 28 |
| L50 | **x3.00** | **12%** | 39,601 | **7** |
| L1000 | x1.00 | 91% | 6,678,136 | 30 |
| L1000 | **x3.00** | **12%** | 62,551,522 | **3** |

Two conclusions, pulling in opposite directions:
- **Under-level farming is already well punished** — fighting things at a quarter of your
  level takes ~1300 fights per level against ~35. This is the reward gradient that item 6
  wanted, and it means the safe-pocket concern near posts is NOT an XP exploit. Good news
  that did not need designing
- **Over-level fighting is wildly over-rewarded.** The optimal strategy by raw throughput
  is to attack monsters **3x your level at a 12% win rate** — 10x faster levelling than
  fighting fair. The sqrt over-level bonus compounds with the monster's own level-scaled
  base XP, so the reward outruns the falling win rate

**That is only optimal if losing is cheap, and under permadeath it is the opposite of
cheap.** An 88% loss rate is character suicide. So the game is currently telling an
optimising player to do the single most destructive thing available. Either:
- the over-level XP bonus is flattened so fair fights are competitive, or
- losing is made survivable (reliable flee), making the gamble a real choice, or
- both, deliberately — the gamble is a fine *option*, it just should not be the best one

- [ ] Decide which, then re-run `-- xp`. This interacts with the Trickster's Outsmart
      identity (its whole design is the over-level gamble) and with 12b's loop, where
      pushing out "as far as you can survive" is the intended pressure

**CORRECTION to the XP finding above (2026-09-02, `-- risk`).** The line "the optimal
strategy is to fight things you lose to" was based on a **throughput** metric — XP per
attempt with losses counted as zero — which is the wrong lens for a permadeath game and
produced a misleading headline. Two things it got wrong:

- **A successful over-level kill is NOT worth 1/7th of a level.** The "7 fights per level"
  figure averaged in the ~88% of attempts that fail. A single successful kill at **3x your
  level pays 1.24-1.93 LEVELS**, and at 5x it pays **4.3-7.9 levels**. The heroic reward is
  already large; the earlier presentation obscured it
- **Over-levelling is not "optimal" at all.** Pricing a loss at zero ignores that a loss
  costs the character. Netted properly it is heavily negative

Measured with a player who fights and then tries to **flee** below 35% HP (real
`process_flee`), so failure is three-way — kill, escape, or permadeath:

| Player | monster | kill% | escape% | death% | reward (levels) | levels per death |
|--------|---------|-------|---------|--------|-----------------|------------------|
| L50 | x1.0 | 58% | 25% | 16% | 0.04 | 0.13 |
| L50 | x1.5 | 19% | 8% | **72%** | 0.19 | 0.05 |
| L50 | x3.0 | 13% | **0%** | 86% | **1.24** | 0.20 |
| L250 | x3.0 | 13% | **0%** | 86% | **1.74** | 0.28 |
| L1000 | x3.0 | 25% | **0%** | 75% | **1.93** | 0.64 |
| L1000 | x5.0 | 8% | **0%** | 91% | **7.91** | 0.72 |

**Killing something 3x your level is already hard** — 13-25%, with 75-86% ending in
permadeath. The user's "it shouldn't be easy" is satisfied by the current numbers.

**The real defect is that you cannot escape.** Escape drops to **0%** against anything
1.5x your level or above. `process_flee` subtracts the full level gap from the chance and
floors it at 10%, so against a monster 100+ levels up it is a 10% roll per turn while
something that outclasses you is killing you in 2-3 turns. So an over-level fight is not a
gamble a player can *play* — it is a coin flip on the character with no skill expression
and no way to bail once it turns.

**And `levels per death` is below 1.0 almost everywhere** (0.01-0.72), meaning the gamble
destroys more progress than it creates. So no rational player takes it, and the whole
over-level reward curve — including the big 1.2-7.9 level payouts — is **dead content that
is never claimed**.

- [x] **Escape fixed (2026-09-02).** `process_flee` subtracted the RAW level gap in
      percentage points, which is meaningless across a 1-10000 range — 100 levels up is a 10x
      monster at L10 and a 10% one at L1000, yet both cost 100 points. Anything meaningfully
      above the player pinned flee to its 10% floor. Same shape of bug as the gear model's
      fixed level-lag: an **absolute** difference used where only a **ratio** has meaning.
      Now the penalty is 30 points per doubling (2x = -30, 3x = -48, 5x = -70) and the floor
      is raised 10 -> 25. **Measured per attempt: 45% at even level, 24-27% at 1.5-5x** (was
      pinned at 10%). Running from something far above you is now always possible, never
      certain, and a decision the player can actually play
- [ ] **Open follow-up: should escaping COST something?** Right now a successful flee is
      free. Dropping carried loot, taking a lasting wound or burning a consumable would make
      disengaging a real trade rather than a pure out. Deliberately not added unilaterally —
      it is a design call, not a bug fix
- [ ] Re-measure the risk/reward table now that escape works, and only then decide whether
      the 1.2-9.3 level payouts need raising. The `-- risk` audit models a player who attacks
      first and flees once hurt; against something far above you that first exchange is often
      fatal, so its escape column understates a player who runs immediately. Worth adding a
      "flees on sight" mode before drawing conclusions from it
- [ ] Only after that, revisit whether the payout curve itself needs raising — with a
      survivable failure mode the same numbers may already be right
- [ ] Sample-size caveat: 36 fights per cell, and the kill% column is visibly noisy
      (L50 shows 2% at x2.0 but 13% at x3.0, which is monster-selection variance rather
      than a real inversion). Widen before tuning against these numbers

**Two code-level notes found on the way, neither fixed yet:**
- [x] **Dead `check_level_up()` removed (2026-09-02).** It computed the requirement as
      `pow(level+1, 2.5) * 100` while the live path uses `pow(level+1, 2.2) * 50` — a ~30x
      divergence by L1000 that any future caller would have silently inherited.
- [ ] **The simulator cannot observe XP grants.** Neither the killing blow nor `end_combat`
      moves `character.experience` in the solo path — combat_manager returns the reward and
      `server.gd` applies it. An earlier version of this audit read XP as a delta on the
      character and reported ~1 fight per level at every level, which was pure measurement
      error. The audit now computes XP from the monster's own `experience_reward` plus
      combat_manager's level-gap arithmetic. Worth remembering for any future reward work:
      **rewards live server-side and the sim is blind to them**
- [ ] **Widen calibration sample size.** 24 fights per level per pass leaves visible noise (one
      L1000 pass read 20 turns against a converged 3-5). Raise it before treating the numbers as
      final
- [ ] **Re-run every balance measurement against the new baseline** — the ability-power table,
      the class comparison and the companion audit were all measured against the old monster
      model and their absolute numbers are now stale
- [ ] **The curve inherits the gear model's known slope error** (item 5): calibrated against a
      `make_char` that is hot at L6 and cold at L45, with only 2 genuinely geared real characters
      to fit against. The shape is now right; the absolute level carries that uncertainty

- [x] **Danger budget is per ENCOUNTER, not per monster (found in playtest, 2026-09-02).**
      First live L5 fight: beat an Orc Weapon Master, then died to the second of its flock. A
      flock chains more monsters into the same encounter with **no healing in between**, so a
      species with a 35% flock chance really presents ~1.5 monsters and a calibrated 40% cost
      per monster becomes 60%+ overall — with the tail (two or three chained, plus a rare
      variant) simply lethal. Each monster's DAMAGE is now divided by the expected chain length
      `1/(1-p)`; HP is untouched so each still takes its target number of turns, and a species
      that never flocks is unaffected
- [ ] Re-run `-- progression` and `-- roles` after the flock change — every danger number above
      was measured before it
- [ ] Decide the target curve first (what *should* win% and danger look like at L10, L100,
      L1000, L10000?), then tune to it. Without a target the sweep has nothing to fail against
- [ ] Fix the **mid-game hump** and the **late-game slide** — the two ends of the same problem

### 6e. Solo combat presentation — port the party pass back (user 2026-09-02)
*Found in the first live playtest of the monster model: "solo combat is missing a lot of the
fixes/improvements we made on party combat — the timing on when healthbars drop, when combat
numbers and animations are played, and anything else that will improve solo combat."*

- [x] **Root cause found and fixed: the playback gate was co-op-only.**
      `_coop_playback_pending()` returned `_in_coop_combat() and queue non-empty`, so in SOLO it
      was **always false** — every result landed the instant the server message arrived while
      the combat text was still draining through the queue. Health bars dropped before the line
      explaining the hit, and damage numbers played out of step with the log. The docstring's
      own reasoning ("anything that shows the RESULT of the round must wait, or it lands before
      the player has seen what happened") never had anything to do with co-op. It now delegates
      to `_combat_playback_active()`, which already computed exactly this — one condition
      instead of two copies to drift apart
- [x] **Added the SOLO settle on queue-drain.** Holding results back requires something to
      apply them when the beats finish. The party paths did that from their own authoritative
      payloads; solo had none, so gating alone would have frozen its bars mid-fight
- [ ] **Verify in a live fight** — this is a timing change and the simulator cannot see it
- [ ] Audit the rest of the v0.9.740 party pass for solo-applicable pieces: the round-budget
      pacing (a co-op round plays to ~6s total, recomputed each beat so it starts brisk and
      eases into the killing blow), the catch-up drain when a newer round is waiting, and the
      Continue-button semantics (hurry / wait / dismiss). Solo has its own per-beat delay and
      may want the same total-budget shape
- [ ] Check whether attack FX still fire at submit rather than on the beat in solo — that was
      one of the five co-op bugs and the same code path serves both

**HIGH-SAMPLE RE-MEASUREMENT (`-- n=90`, 2026-09-02).** Supersedes every balance number taken
before it. Calibration convergence raised from sqrt to `CAL_CORRECTION_EXP = 0.75` over 6 passes
— justified by the sample budget going from 8 to 30 fights per class, which is what the heavy
damping had been protecting against.

**Roles — the danger axis converged for NORMAL, partially for elite, not for boss:**

| Role | turns (target) | HP cost (target) | win% |
|------|----------------|------------------|------|
| normal | 5.6 / 5.2 / 5.1 / 3.3 / 3.0 / **2.6** (5) | 40 / 30 / 41 / 48 / 44 / 43% (**40%**) | 65-82% |
| elite | 6.0 / 7.3 / 5.9 / 3.7 / 12.7 / 3.5 (9) | 39 / 52 / **65** / **68** / 44 / 44% (70%) | 47-78% |
| boss | 9.6 / 9.5 / 8.4 / 23.1 / 8.9 / 15.5 (14) | 48 / 50 / 57 / 57 / 58 / 35% (85%) | 55-76% |

*(levels L1 / L10 / L50 / L250 / L1000 / L5000)*

- **Normal fights now cost exactly their 40% target**, up from 33%. The convergence fix worked
- **Elite reaches 65-68% at L50-250** (target 70%) but sags at both ends
- **Boss is still well short** — ~50-58% against 85%. Bosses are a real fight but not frightening
- [ ] **The remaining structural gap: high-level fights are too SHORT.** Normal turns fall to
      3.3 / 3.0 / **2.6** at L250 / L1000 / L5000 against a target of 5. Monster HP is
      under-converging at the top end while the danger axis is on target, so the top of the game
      is quick rather than easy — a different fault from the old sawtooth and a smaller one
- [x] **Roles are now CALIBRATED, not derived (2026-09-02, `-- rolecal`).** The derivation
      assumed a fight really lasts `turns_role`, which it does not, so damage never accumulated
      to the intended cost. Measured multipliers replace it: empowered hp x1.31 / str x1.48,
      elite hp x2.35 / str x1.72, boss hp x3.32 / str x1.72. `monster_database` prefers these
      over the algebra whenever the curve file carries them.

      **The danger targets are now HIT — and that is the problem.** Verified at n=90:

      | Role | target cost | measured cost | measured WIN% |
      |------|-------------|---------------|---------------|
      | normal | 40% | 43% | **74%** |
      | empowered | 55% | 57% | **60%** |
      | elite | 65% | 67% | **46%** |
      | boss | 80% | 75% | **34%** |

- [x] **DECIDED (user, 2026-09-02): the measured costs are the intent** — normal 43%,
      empowered 57%, elite 67%, boss 75% of the player's health bar. The coupled win rates
      (74 / 60 / 46 / 34%) were put to the user explicitly, including that a 34% boss win rate
      under permadeath is roughly three characters lost per boss killed, and accepted.
      **`ROLE_TARGETS` is deliberately left UNCHANGED at 40/55/65/80** — those are the *inputs*
      that produced the approved *outputs*; retargeting to the measured values would aim the
      calibrator lower and undershoot what was agreed
- [x] **Level unevenness largely CLOSED (2026-09-02) by single-axis, per-level role
      calibration.** Four approaches were measured against each other:

      | approach | elite cost (t65) | elite win spread | boss win |
      |----------|------------------|------------------|----------|
      | one derived pair | 57-77% | 28 pts | 23-47% |
      | per-level, 2-axis | 37-67% | 23 pts | 30-47% |
      | win-only turns | 63-81% | 24 pts | **15-33%** (worse) |
      | **single-axis, per-level** | **54-68%** | **12 pts** | 30-48% |

      Final: elite cost 54-68% against a 65% target with win rate in a **12-point band**
      (48-60%), down from 28. Boss cost 65-81% against 80%, win 30-48%. Normal 35-55%
      against 40%, win 64-82%.

      **Two failed attempts are recorded because both looked obviously right:**
      - *Measuring fight length on WINS ONLY* — reasonable-sounding (a "14-turn boss fight"
        describes a fight you win) and **actively harmful**: conditioning on wins SELECTS the
        favourable, SHORT fights, so it reads short exactly when win rate is low, the
        calibrator raises HP, win rate drops, and the next pass selects even more lopsided
        wins. Boss win fell to 15-33%
      - *Correcting turns AND cost together* — they are coupled through the win rate (raising
        HP raises cost, which kills the player sooner, which shortens the fight), so two knobs
        chasing two coupled targets oscillate instead of converging

      **Turn count is now an OUTPUT, not a target.** `hp_mult` is fixed at the role's design
      length ratio with no feedback; only cost is corrected. Measured turns range widely
      (2.9-32.2) and that is accepted: the danger numbers were signed off, fight length was
      not. Tunable directly via `ROLE_TARGETS.turns` with no loop to destabilise
- [ ] Remaining, and smaller: boss cost averages 71% against its 80% target, and empowered has
      one outlier at L1 (32% against 55%). Worth one more pass some time, not now
- [ ] **Superseded note — the original statement of this problem:** With
      the targets settled, this is what is left, and it is the old hump in miniature:

      | Level | elite win | boss win |
      |-------|-----------|----------|
      | L1 | 63% | 40% |
      | **L10** | **38%** | **24%** |
      | **L50** | **35%** | **23%** |
      | **L250** | 38% | 35% |
      | L1000 | 45% | 47% |
      | L5000 | 62% | 37% |

      Elite spans 35-63% and boss 23-47% against targets of one number each. **L10-L250 is the
      punishing band** — a boss there is won 23-24% of the time against 47% at L1000, so the
      same nominal encounter is twice as lethal in the mid game. The role multipliers are a
      single pair applied at every level, so they cannot correct a level-dependent gap
- [ ] Candidate fix: make the role multipliers **per-anchor** (calibrated per level like the
      baseline already is) rather than one pair for the whole game. Same change also addresses
      the turn-count drift below, since both come from one multiplier serving four orders of
      magnitude
- [ ] Turn counts are still off target for the big roles (boss 6.4-17.7 against 14, elite
      5.5-14.6 against 9) even with calibrated multipliers — a single multiplier cannot hold
      both length and cost across the level range. Secondary to the decision above
- [ ] The 40 / 70 / 85% danger targets are a **proposal, not a measurement** — worth the owner's
      eye before more work is spent hitting them exactly

**Ability power (`-- ability_hp`), one cast as % of a same-level normal monster's bar:**

| Ability | L1 | L10 | L100 | L1000 | L5000 | L10000 |
|---------|----|-----|------|-------|-------|--------|
| power_strike | 16% | 16% | 16% | 33% | 61% | 123% |
| cleave | 21% | 19% | 19% | 41% | 108% | 126% |
| ambush | 14% | 14% | 16% | 24% | 35% | 67% |
| gambit | 14% | 15% | 21% | 34% | 47% | 57% |
| exploit | 10% | 11% | 26% | 48% | 33% | 18% |
| **magic_bolt** | 61% | 42% | 53% | **170%** | **481%** | **379%** |
| **blast** | 51% | 27% | 19% | 16% | 15% | 25% |
| meteor | 196% | 87% | 28% | 47% | 52% | 73% |

- **Magic Bolt is confirmed as the outlier, and it is worse than first measured** — 42% of a
  health bar at L10 rising to **481%** at L5000, an ~11x drift. Every other ability moves by
  ~4x across the same span. Its `mana x (1 + 4.3*sqrt(INT))` shape rides a mana pool that grows
  faster than level, and nothing else in the game does that
- **Blast has stabilised** at 13-27% rather than dying to 5% as it did against the old baseline —
  it is weak and flat, not collapsing. A smaller problem than it looked
- **The warrior/trickster rise at the top end (power_strike 123%, cleave 126%) is NOT an ability
  problem** — it tracks the too-short high-level fights above. Fix the HP convergence and these
  should settle back; do not tune them first

### 6g. **DONE — ability anchor decoupled; curve smoothed** (2026-09-02)

*Was: "`refcal` cannot steer fight length". User approved the frozen-bar fix.*

**The defect.** Ability damage was `reference_monster_hp(level) * weight * stat_ratio` — a share
of the SAME curve `refcal` rewrites. Raising monster HP to lengthen a fight raised every
ability's damage by the identical factor, so fight length never moved and the calibrator kept
raising HP: **2-5x inflation across every anchor** over repeated runs, while abilities kept pace
and BASIC ATTACKS (which do not scale with it) silently fell behind. Companion damage had the
same coupling and was fixed alongside.

**The fix.** `shared/ability_reference_bar.json` — a frozen snapshot of the curve the
`ABILITY_WEIGHTS` were authored against, which `refcal` must never rewrite. Ability and
companion damage read it; monster HP is an independent lever again. **Consequence worth
stating: "a power strike is worth a fifth of a monster" is now a claim about the FROZEN bar, not
about whatever monsters currently have.** If calibration decides monsters need 1.5x HP, a power
strike becomes a seventh of one. That is what makes fight length steerable at all, but it means
`ABILITY_WEIGHTS` wants re-reading against `-- ability_hp` once the curve settles.

**A second defect the fix exposed.** The monotonic clamp stops dips, but turns a single noisy
SPIKE into a permanent plateau: L250 spiked to 35351 and L500 — which had calibrated itself to
16106 — was clamped UP to 35351, inflating every level above it. The curve stepped 5.04x from
L100 to L250 then 1.00x to L500, and the role audit landed exactly on those anchors (L250 normal
16.4 turns, L1000 boss 3.1). Now smoothed in log space BEFORE clamping, two light passes.

| | before | after |
|---|--------|-------|
| step between anchors | 1.00x - 5.37x | **1.07x - 2.31x** |
| monotonic | 3 clamps needed | **True, no clamps fired** |

**THREE measurement bugs in the simulator were found and fixed today.** Every one made the game
look different from how it actually plays, so treat historical numbers in this file with care:
- `_fight_stats_at` counted every win TWICE (the same `if` appeared twice in a row) — every win
  rate that function ever printed was **2x the truth**. Display only; calibration corrects on
  turns and cost, so written curves were unaffected
- `refcal` printed the measurement from one correction BEFORE the value it wrote
- smoothing and clamping run AFTER the per-anchor loop, so the printed table described numbers
  that no longer existed. Rows are now labelled `raw / pre-smoothing` and a verification table is
  measured against the final written curve — **that is the only table to trust**

**Where the curve landed** (roles audit, n=60, post-smoothing):

| role | HP cost before | HP cost now | target | win% |
|------|----------------|-------------|--------|------|
| normal | 28-56% | 44-57% | 40% | 61-78% |
| empowered | 23-54% | 46-59% | 55% | 58-71% |
| elite | 24-58% | 51-71% | 65% | 43-63% |
| boss | 32-70% | 54-73% | 80% | 43-66% |

Danger converged and win rates now descend correctly by role — empowered used to be EASIER than
normal. L1-L100 lands at 4.5-6.5 turns against a 5-turn target.

**ROLE CALIBRATION landed — bosses are dangerous again.** `-- rolecal`, per anchor level:

| role | HP cost | target | win% |
|------|---------|--------|------|
| empowered | 39-73% | 55% | 50-80% |
| elite | 49-72% | 65% | 53-73% |
| **boss** | **69-85%** | **80%** | **27-50%** |

A boss now costs ~three quarters of the bar and is lost more often than won. Before this session
it cost half a bar at a 60-73% win rate.

**A FOURTH tooling bug, and this one destroyed committed work rather than misreporting it.**
`refcal` wrote the curve file with only `anchors`, so running it after `rolecal` silently wiped
`role_multipliers` — the boss fix above was measured, reported, and then overwritten by the very
next `refcal` run. The documented workflow at the top of CLAUDE.md is `refcal` then `roles`, and
`roles` is a READ-ONLY audit, so following it exactly was safe — the trap is that `rolecal` (the
writer) is not in that workflow, so any later `refcal` silently discarded it with no warning and
no visible symptom until a role audit was re-run. `refcal` now carries the block forward
and prints a note when it does. Only caught because a manual file restore happened to print
"no role_multipliers in current file".

**A correction attempt that FAILED, recorded so it is not retried.** Correcting monster HP
against EFFECTIVE turns (fight length extrapolated to completion from damage dealt, to escape
death-truncation) made the low game worse: L1-L100 fell from 4.5-6.5 turns to 2.5-3.0 against a
5-turn target, L50 HP 6296 -> 3612. For a WON fight eff_turns equals observed turns; for a lost
one it extrapolates upward, so the mean is always >= observed, and the calibrator concluded
fights ran long. The premise was wrong: a player who dies on turn 4 experienced a 4-turn fight
against a monster that is too STRONG, which the danger axis already handles. `eff_turns` is
still measured and reported — the truncation it describes is real — but it is not the correction
signal. Reverted.

**EMPOWERED INVERSION FIXED (2026-09-02).** `rolecal` had the same measure-then-correct lag
`refcal` did — the written multiplier was one correction past the last measurement — so
empowered was pushed to 59-74% HP cost against a 55% target, ABOVE elite in the middle band.
With a verification pass and 8 passes instead of 5, `str_mult` fell from 1.46/2.07/1.27 to
0.96/1.63/0.78 and the tier order is correct again:

| role | HP cost | target |
|------|---------|--------|
| normal | 39-54% | 40% |
| empowered | 49-74% | 55% |
| elite | 65-80% | 65% |
| boss | 71-89% | 80% |

**Boss danger CONFIRMED as intended (user 2026-09-02):** *"I think I'm okay with the bosses
currently as I think companions and gear will make up the difference."* Boss win rate sits at
18-46%. Do not re-open this as a defect — it is a decision.

- [ ] **UNRESOLVED: the calibrators and the `roles` audit disagree by ~6-8 points on the same
      quantity, consistently in one direction.** `rolecal` measures empowered at 49-65%; the
      audit measures the same written multipliers at 59-74%. It is not confined to one role —
      `normal`, tuned by a completely different calibrator (`refcal`/`_fight_stats_at`), also
      reads 46% mean against its 40% target. So two independent calibrators each hit their
      target by their own measurement while the audit says all four run hot. Both paths build
      characters the same way (`make_char(lvl, "average", klass)`, same three classes); the
      audit uses 20 samples/class against the calibrators' 10, which explains noise but not a
      one-directional bias. **Find which of the two is lying before trusting either number.**
      Given four measurement bugs in this tool today, assume it is a real defect, not variance

- [ ] **Turn counts still swing** and this is now the LAST big open item on the curve (boss
      L5000 43.7 turns, empowered L10000 48.1). Danger converged because `str` is a clean
      independent lever; turns did not. Note `rolecal` deliberately does NOT calibrate
      `hp_mult` — it is fixed at the role's design length ratio (1.40/1.80/2.80) with no
      feedback, so **role fight length inherits the base curve's turn error and multiplies it**.
      Boss L250 is 30 turns because normal L250 runs long. Fix the base curve, not the roles.
      Two failed approaches so far: feeding both axes back (oscillates) and effective turns
      (above). A joint two-variable solve is the untried option
- [ ] Re-read `ABILITY_WEIGHTS` against `-- ability_hp` now the bar is frozen and the curve moved
- [ ] Re-run `-- classes`, `-- species` — both were measured against the stale curve

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

**CORRECTION 2026-09-02 (traced the consumption paths).** An earlier version of this item
claimed "companion passive stat bonuses do not scale with level at all — a L1 Ogre and a
L10000 Ogre grant the identical `{attack 5, hp_bonus 3}`". That was read off
`get_companion_effective_bonuses` alone and is **wrong in its implication**. The table values
are **percentages**, and every consumer applies them to a base that already scales:
- `attack` multiplies companion damage: `(tier*5 + player_level*0.3 + companion_level*0.5)
  * (1 + attack/100)` (`drop_tables.get_companion_attack_damage`)
- `hp_bonus` / `mana_bonus` are `% of the player's own max`
  (`get_total_max_hp() * comp_hp_bonus / 100.0`)
So a +5% companion is +5% at every level, like a gear affix. Nothing is "decorative".

**What actually explains `comp L1` ≈ `none`** is almost certainly **ability unlocks**, not stat
bonuses: `get_companion_unlocked_abilities` grants the passive always, the **active at
companion level 5**, and the **threshold at level 15**. A level-1 companion has *one third of
its kit*, which matches the measurement far better than a percentage that never changed.

**SHIPPED 2026-09-02 — two companion durability defects found in live play (L50 Wizard).**

1. **Aggro was rolled once per ROUND but applied the whole round's damage.** A `multi_strike`
   monster put its entire burst on whichever target won a single coin flip, so a Gryphon's
   3-hit round — ~45% of the player's bar — took ~90% of a companion's smaller pool at once
   ("it nearly killed my Succubus in one hit"). Aggro is now rolled **per hit** and a round can
   split across both targets. Expected soak is *unchanged* (25% aggro takes 25% of hits instead
   of 25% of rounds); only the burst spike is gone. This is not a companion buff.

2. **HP share was a flat 0.5 regardless of how many hits the companion is asked to take**, which
   made relative durability the **inverse of the design intent**. Lifetime vs the owner is
   `share*(1-a)/a`, so at a flat 0.5:

   | companion | aggro | lifetime vs owner |
   |-----------|-------|-------------------|
   | Iron Golem | 65% | **0.27x** — the tank died ~4x FASTER than its owner |
   | Wolf | 25% | 1.50x |
   | Succubus | 12% | **3.67x** — the glass caster was the survivor |

   A 21x spread with the designated soakers at the fragile end. Share is now solved from aggro
   (`COMPANION_LIFETIME_TARGET = 1.25`), clamped **below by the old 0.5** so no existing
   companion can be weakened — the standing rule that player investment is never downscaled.
   Spread 21x → 5x; an Iron Golem goes 0.5 → 2.0 share.

**The share is NOT a share of the player's HP** — a recurring misreading, recorded here so it
is not re-derived. It multiplies `max(owner_side, own_side)`, and for any invested companion the
**own-level anchor wins outright**:

| case | owner HP | owner_side | own_side | compHP |
|------|----------|-----------|----------|--------|
| L50 owner, L50 Succubus | 659 | 659 | 659 | 330 |
| L50 owner, L50 Iron Golem | 659 | 659 | 659 | 1318 |
| **L10 owner, L250 Succubus** | 120 | 120 | **2260** | **1130** |
| **L10 owner, L250 Iron Golem** | 120 | 120 | **2260** | **4521** |

A L250 companion on a L10 character has ~9.4x that character's HP. The owner's level never
enters the result once the companion out-levels them. `tools/probe/comp_hp_probe.gd` prints this
table on demand.

- [ ] **Still open: a matched companion survives only ~3 rounds at L1000** (`-- comp_unlock`,
      soaking 0.6 hits/fight) even after both fixes. Win% with one is 63% against 6% without, so
      companions carry enormous weight up there — but they are being knocked out early in the
      long fights. Re-measure after the curve re-calibration below before tuning further
- [ ] **Re-run `-- refcal` + `-- roles`.** Companion durability is a PLAYER-SIDE power change, so
      per the top-of-CLAUDE.md rule the monster curve is now stale. This already bit once when
      the companion HP rework pushed elite-at-L1 to 90% against a 70% target

**MEASURED 2026-09-02 (`-- comp_unlock`) — it is companion HP, not unlocks, not bonuses.**

The user's read was right and both of the assistant's hypotheses were wrong. Same-level ELITE,
Fighter, average gear, 24 fights/cell. `survived` = rounds up before KO, `soaked` = hits the
monster spent on the companion instead of the player:

| Player | comp level | comp HP | survived | soaked | win% |
|--------|-----------|---------|----------|--------|------|
| L5 | none | 0 | – | – | 50% |
| L5 | 1 | 45 | 18.3 | 2.7 | 54% |
| L5 | matched | 65 | 12.2 | 1.8 | 79% |
| L50 | 1 | 45 | **2.6** | 0.5 | 20% |
| L50 | matched | 290 | 5.9 | 1.2 | 41% |
| L250 | matched | 1,290 | **4.0** | 1.0 | 58% |
| L1000 | 1 | 45 | **1.3** | 0.3 | 50% |
| L1000 | matched | 5,040 | 20.9 | 7.5 | 79% |
| L10000 | none | 0 | – | – | 16% |
| L10000 | 1 | 45 | **2.6** | **0.1** | 12% |
| L10000 | matched | 50,040 | 27.3 | 6.1 | 50% |

- **`calculate_companion_max_hp` is `30 + level*5 + sub_tier*10 + hp_bonus` — linear**, while
  monster damage is now anchored to a player curve that is not. A level-1 companion has **45 HP
  at every level in the game**: at L10000 it survives 2.6 rounds, soaks **0.1 hits**, and wins
  12% against 16% for no companion at all. It is not a sponge and not an attacker; it is a
  casualty. That is the real explanation for "comp L1 == none"
- **The ability-unlock hypothesis is DISCONFIRMED.** There is no step at companion level 5 or
  15 — L1000 reads 50% / 66% / 41% for comp levels 1 / 5 / 15, which is noise. Only `matched`
  separates, and it separates by HP
- **Even a level-MATCHED companion dies mid-fight through the mid game** — 5.9 rounds at L50,
  **4.0 rounds at L250** against a fight designed to last 9. This is the user's reported
  frustration measured directly: *"companion HP always seems rather low, they die frequently
  and players have to go back to a post to bring them back to life"*
- Note also a genuine units inconsistency: `hp_bonus` is added **flat** here but consumed as a
  **percentage** of the player's max HP in `combat_manager` (`get_total_max_hp() * bonus/100`).
  The same table field means two different things in two places

**Proposed fix — anchor companion HP to the player, the way monsters now are:**

    companion_max_hp = player_max_hp * share(tier, sub_tier) * f(comp_level / player_level)

with `share` around 0.35-0.60 and `f` clamped (say 0.25-1.25) so an under-levelled companion is
weaker but never a one-hit casualty, and an over-levelled one saturates. Consequences:
survivability holds at every level by construction; levelling a companion pays visibly; and the
constant trek back to a post to revive largely goes away.

- [x] **IMPLEMENTED 2026-09-02** with `COMPANION_HP_SHARE = 0.5` (user's number): companion HP
      is now `owner_max_hp * 0.5 * g(comp_level/owner_level) * sub_tier_mult * hp_bonus_mult`.
      `g` is deliberately **asymmetric** — floored at **0.60** so an under-levelled companion
      stays a real body rather than a one-hit casualty, and rising to **2.5** so an
      over-levelled one genuinely **carries** rather than being clamped to parity. That second
      half is the mechanical form of the design premise that a registered companion pulls a
      fresh character forward, and of the setting's line that companions outlive their delvers.

      **Measured after (`-- comp_unlock`), win% at same-level elite:**

      | Player | none | comp L1 | matched | carry (10x level) |
      |--------|------|---------|---------|-------------------|
      | L5 | 50% | 50% | 54% | **83%** |
      | L50 | 25% | 33% | 45% | **75%** |
      | L250 | 45% | 20% | 62% | **75%** |
      | L1000 | 41% | 54% | 75% | 66% |
      | L10000 | 8% | 16% | 50% | 37% |

      Under-levelled companions went from useless to useful (L50 comp-L1: 20% -> 33-41%, with
      HP 45 -> ~178). The carry case lands hardest exactly where it should — at L5-L250, where
      a fresh character is being pulled through. At L1000+ "carry" converges on "matched"
      because companion level is capped at 10000, so there is nothing left to carry with.
- [x] Reconciled the `hp_bonus` units bug in the same pass — it is a **percentage** everywhere
      now, matching how `combat_manager` already consumed it
- [x] Both client-side mirrors of the formula updated. `client.gd` now calls the real static
      function instead of re-deriving it; the combat panel keeps a placeholder only for the
      frame before the authoritative `combat_update` lands
- [x] **Live playtest at L250 PASSED (2026-09-02).** User: *"Companion did survive the fight
      but was taking adequate damage. Companion HP bar timing seemed right."* That is precisely
      the target — a companion that survives a fair fight while still being at risk, rather
      than either a one-hit casualty or an invulnerable pet. `COMPANION_HP_SHARE = 0.5` is
      confirmed by feel, not just by simulation
- [x] **No-downscaling requirement verified** — a L250 companion measures 1130 HP beside owners
      at L10 / L50 / L250 / L1000 alike. Beside a fresh character that is eight times their own
      health bar
- [ ] **The companion buff moved the whole difficulty curve** and the monster curve was
      calibrated BEFORE it. The reference player is now meaningfully stronger, so monsters are
      undersized: measured after the change, elite at L1 reads **90% win at 28% HP cost against
      a 70% target** (it was 56% before). Re-calibration is running; **any balance number taken
      between the companion change and that re-calibration is stale**
- [ ] Sample noise: 24 fights/cell, and some rows invert (L250 comp-L1 reads 20% against 45%
      for no companion). Widen before treating any single row as real
- [ ] `calculate_companion_max_hp` is **static and takes only the companion dict**, so it has no
      access to the player. Threading the owner through is the main implementation cost; check
      every caller, including any client-side mirror
- [ ] Reconcile the `hp_bonus` flat-vs-percentage inconsistency in the same pass
- [ ] Re-run `-- comp_unlock` after the change; it is the regression test for this item
- [ ] Companion **damage** also scales linearly (`player_level*0.3 + companion_level*0.5`)
      against content that no longer does. Same class of problem as the HP; fix together

- [ ] Make companion **stat bonuses scale with companion level**, not just variant/sub-tier —
      this is what makes a fresh companion feel like nothing at all today
- [ ] Find and fix the **high-level saturation** (x10 stops beating level-matched past ~L5000)
- [ ] Re-shape ability scaling so it keeps pace with content rather than falling behind
- [ ] Give levelling a companion a **visible, worthwhile payoff curve**; make the ways to
      improve one (levels, fusion, sub-tier, variants) legible and reachable
- [ ] Re-run `-- companion` after each change; it is the regression test for this item

### 6c. Class balance & the resource economy — ability shapes FIXED; class tuning remains
*Split out of item 6 on 2026-09-02: item 6 had grown to 21 open tasks covering two different
jobs — sizing the MONSTERS and sizing the CLASSES. They are separate, and the second depends on
the first being settled.*

**Prerequisite DONE (2026-09-02): re-measured against the new baseline.** The numbers below
are current; anything quoted from before the reference-player model landed is superseded.

**RE-MEASURED against the reference-player baseline, 2026-09-02.** These supersede every
class/race number taken before the monster model changed.

**Classes** (`-- classes`, 60 fights/cell, average gear, win% / turns / casts-per-turn):

| Class | path | L10 normal | L30 elite | L80 elite |
|-------|------|-----------|-----------|-----------|
| Fighter | warrior | 81% | 45% | 50% |
| Barbarian | warrior | 65% | 41% | 48% |
| **Paladin** | warrior | 50% | **31%** | **36%** |
| Wizard | mage | 80% | 40% | 38% |
| Sorcerer | mage | 66% | 53% | 45% |
| **Sage** | mage | 66% | **20%** | **18%** |
| Thief | trickster | 56% | 56% | **80%** |
| Ranger | trickster | 45% | 45% | 63% |
| Ninja | trickster | 51% | **75%** | 71% |

- Elites are now genuinely hard, which is the ROLE_TARGETS design (9 turns, 70% of the bar)
  rather than a regression
- **Sage is the worst class in the game by a wide margin** — 20% and 18% where its own
  archetype siblings sit at 40-53%. Its passive is 25% cheaper mana, which is worth least
  in exactly the fights that matter. First thing to look at
- **Paladin is second-worst** (31/36 against Fighter's 45/50) and the slowest (17 turns at
  L80 elite)
- **The trickster lead persists** and widens with level (Thief 80%, Ninja 71% at L80 elite).
  Likely mechanism already identified: Exploit is the only ability whose damage is a
  percentage of target max HP

**Races** (`-- races`, L30 elite) — a real ~20-25 point spread, previously invisible because
`make_char` hardcoded Human:

| Race | Fighter | Wizard | Thief |
|------|---------|--------|-------|
| Human | 50% | **58%** | 75% |
| Elf | 48% | 53% | 63% |
| Dwarf | 41% | 50% | **76%** |
| **Ogre** | 41% | **33%** | **51%** |
| Halfling | 51% | 51% | 75% |
| Orc | 38% | 48% | 68% |
| Gnome | 45% | 36% | 66% |
| **Undead** | **28%** | 50% | 66% |

- **Human is at or near the top for every archetype**, which is backwards: its trait is +10%
  XP, an out-of-combat bonus. A race with no combat trait leading combat means the other
  races' traits are underpowered or not firing
- **Undead (28% Fighter) and Ogre (33% Wizard) are the weak ends.** Ogre's trait is doubled
  healing received and Undead's is curse immunity + poison healing — both situational, and
  worth nothing in a fight that contains neither
- [ ] Check whether the situational racial traits ever actually trigger in combat before
      re-balancing their numbers — a trait that never fires is a UI problem, not a tuning one

**Companions** (`-- companion`, same-level elite, Fighter) — the gap is now large and holds
at every level, which it did not appear to under the old model:

| Level | none | comp L1 | comp L=char | comp x10 |
|-------|------|---------|-------------|----------|
| L50 | 7% | 40% | 30% | 72% |
| L1000 | 37% | 45% | 75% | 82% |
| L2500 | 12% | 17% | 50% | 45% |
| L10000 | 10% | 15% | **50%** | 50% |

- **A levelled companion is worth ~35-40 points of win rate** at high level (10% -> 50% at
  L10000). Companions are now clearly load-bearing, which makes 6b more urgent, not less
- **`comp L1` is still statistically indistinguishable from `none`** at the top end (10 vs 15,
  12 vs 17) — the flat-stat-bonus finding survives re-measurement
- **The x10 saturation also survives** (L10000: matched 50%, x10 50%; L2500: 50 vs 45) —
  over-levelling a companion past your own level stops paying

**Ability power** (`-- ability_hp`, one cast as % of a same-level normal monster's health
bar). **The monster model fixed the early game on its own, without touching a single
ability:**

| Ability | L1 | L5 | L50 | L100 | L1000 | L10000 |
|---------|----|----|-----|------|-------|--------|
| power_strike | **15%** (was 263%) | 10% | 15% | 18% | 25% | 16% |
| cleave | **20%** (was 337%) | 14% | 17% | 20% | 33% | 18% |
| ambush | **18%** (was 261%) | 11% | 13% | 15% | 22% | 15% |
| exploit | 9% | 10% | 17% | 17% | 17% | 16% |
| gambit | 13% | 9% | 16% | 28% | 24% | 12% |
| **magic_bolt** | **60%** (was 1203%) | 36% | 37% | 43% | **123%** | **269%** |
| **blast** | 63% | 32% | 10% | 44% | 13% | **5%** |
| meteor | **193%** (was 3463%) | 87% | 30% | 27% | 36% | 18% |

- **The early-game trivialisation is gone.** Every damage card used to be 2.6x-35x overkill on
  a same-level monster at L1; nothing one-shots now. That was the reported "Magic Bolt is
  extremely powerful early game" problem and it is **fixed as a side effect of anchoring
  monsters to the player** — no ability was touched
- **Warrior and trickster kits are now flat across four orders of magnitude** (10-40% of a
  health bar from L1 to L10000). That is what "balance holds throughout the game" looks like
- **The mage roster is now the isolated problem**, and it is two opposite failures in one kit:
  - [ ] **Magic Bolt is the only ability that outscales** — 36% at L5 rising to **269%** at
        L10000. Its `mana x (1 + 4.3*sqrt(INT))` shape rides a mana pool that grows faster
        than level
  - [ ] **Blast dies** — 63% down to **5%**, so mage sustain evaporates while its burst
        inflates. This is the mechanism behind Wizard's 40-155 turn fights
  - [ ] Meteor decays from 193% to 18% and needs re-siting against the other two
- **Correction to an earlier hypothesis:** the trickster lead was attributed to Exploit being
  the only %-max-HP ability. Against anchored monsters Exploit is now **flat at 9-25%**, yet
  tricksters still lead the class table (Thief 80%, Ninja 71% at L80 elite). So Exploit is not
  the driver — look at Outsmart's instant-win and the dodge/speed advantage instead

- [ ] **Mage roster rework — the clearest class problem, now measured on a clean baseline.**
      Final n=90 run, after the stale-curve and monotonic-ramp fixes, one cast as % of a
      same-level normal monster's health bar:

      | Ability | L10 | L100 | L1000 | L10000 | drift |
      |---------|-----|------|-------|--------|-------|
      | **magic_bolt** | 39% | 80% | 114% | **467%** | **~12x** |
      | power_strike | 13% | 33% | 16% | 128% | ~9x |
      | cleave | 15% | 39% | 23% | 123% | ~8x |
      | gambit | 10% | 49% | 17% | 47% | ~4x |
      | ambush | 10% | 33% | 17% | 31% | ~3x |
      | exploit | 10% | 17% | 28% | 24% | ~2x |
      | blast | 24% | 19% | 10% | 27% | flat, low |
      | meteor | 73% | 51% | 24% | 38% | flat (but 175% at L1) |

      - **Magic Bolt is unambiguous.** It has now measured 269 / 481 / 505 / 467% at the top end
        across four different baselines — the number moves, the verdict does not. Its
        `mana x (1 + 4.3*sqrt(INT))` shape rides a pool that grows faster than level, and
        nothing else in the game does
      - **Warrior burst is a secondary riser** — power_strike 128% and cleave 123% at L10000,
        ~8-9x drift. Not as severe, but the same shape and worth fixing in the same pass
      - **Tricksters are the best-behaved kit** (2-4x drift, flat 10-31%) — the shape to aim for
      - **Blast is weak but stable** (10-27%), not collapsing as it appeared against the old
        baseline. A smaller problem than first reported
      - **Meteor is 175% at L1** — the last remaining early-game one-shot Burst inflates while
      sustain evaporates, which is the mechanism behind Wizard's very long fights. **Sage is
      the worst class in the game** (20%/18% at L30/L80 elite) — its 25%-cheaper-mana passive
      is worth least in exactly the fights that decide things
- [ ] **Trickster lead** (Thief 80%, Ninja 71% at L80 elite against Paladin's 36%). The
      earlier hypothesis — that Exploit's %-max-HP damage was the driver — is **disconfirmed**
      by the re-measurement: against anchored monsters Exploit is flat at 9-25% like everything
      else, yet tricksters still lead. Look at Outsmart's instant-win and the dodge/speed
      advantage instead
- [ ] **Paladin is second-worst and slowest** (31%/36%, 17 turns at L80 elite)
- [ ] **Magic Bolt flat curve** — damage-per-mana has to scale on the same curve as monster HP
**RESOURCE ECONOMY DISSOLVES WITH LEVEL — measured 2026-09-02 (`-- economy`).**
Reported from live play: *"Blast shows it costs 0 but did 1900 damage... this may be a problem
for warriors and tricksters as well."* It is, and it is all three archetypes.

Costs ARE charged — the "0" on screen is regen refilling the spend within the same turn — but
they are trivial relative to the pool:

| Level | Ability | cost | pool | cost% | **casts per full bar** |
|-------|---------|------|------|-------|------------------------|
| L10 | blast | 34 | 130 | 26% | **4** |
| L10 | ambush | 20 | 114 | 18% | **6** |
| L1000 | power_strike | 66 | 3,192 | 2.1% | **48** |
| L1000 | cleave | 100 | 6,093 | 1.6% | **61** |
| L1000 | blast | 185 | 16,363 | 1.1% | **88** |
| L1000 | ambush | 104 | 7,057 | 1.5% | **68** |
| L1000 | magic_bolt | 3,171 | 15,858 | 20% | **5** |

**The resource system works at low level and evaporates by mid-game.** At L10 a mage gets 4
casts of Blast and has to think; at L1000 they get **88** and cannot run out. Every archetype is
affected — warriors 48-61 casts, tricksters 68 — so this is not a mage problem.

**Cause, and it was a deliberate decision rather than an oversight.** Ability cost scales with
the **naked pool** (base + primary stat, excluding gear), by design: the #55 comment states the
intent as *"gear +max pool no longer inflates cost, so a high-cap/high-regen build gets MORE
casts + better sustain."* That intent is reasonable. The magnitude is not: at L1000 a Wizard's
naked pool is ~800 against a total of 16,363, so **gear multiplies the pool ~20x while costs
stay fixed to the naked value** — and 20x more casts is the whole resource economy gone.

Magic Bolt is the only ability that still costs anything (20% of pool, 5 casts) because its cost
is the player's explicit spend rather than a table lookup. That is why it felt so expensive
next to everything else — it was the only card actually paying.

- [ ] **DECISION NEEDED: how much should gear inflate casts-per-bar?** Options:
      1. Cost as a % of the **total** pool — removes the gear reward entirely, simplest, and
         makes casts-per-bar constant at every level
      2. Cost as a % of a **blend** (naked + a capped share of the gear bonus) — preserves the
         intent that gear improves sustain, but bounds it to something like 1.5-2x rather than
         20x. **Recommended**
      3. Cap the gear pool bonus itself — touches more systems
- [ ] Whatever is chosen, target a **casts-per-bar band** (something like 5-10) and hold it
      across levels, rather than targeting a cost percentage. Casts-per-bar is the number a
      player actually experiences
- [ ] `devastate` reads cost 0 at every level — it is a Momentum dump and pays in Momentum
      rather than stamina. Worth confirming that is intended and not a second free-cast path
- [ ] Once costs are real again, **re-check every damage number in 6c**: ability weights were
      tuned assuming a cost that is not currently being paid
- [ ] Anti-abuse items that **never landed**: Forethought and Recharge still exist, no mitigation
      cap, no stun DR. Related user direction: remove blue "skip the enemy turn / refund
      resources" utility cards
- [ ] Equipment vs race vs class, compared **against each other** rather than in isolation
      (`-- races` and `-- classes` now exist for this)

**6c ABILITY WORK COMPLETE (2026-09-02).** Every damage ability now reads off ONE anchor —
a share of the health bar it is fighting — instead of inventing its own scaling curve.

| Ability | before | after |
|---------|--------|-------|
| power_strike | 13% → 128% (9.8x drift) | **~20% flat L1-L1000** |
| cleave | → **213%** at L10000 | **~25% flat L1-L2500** |
| magic_bolt | 39% → **467%** (12x drift) | **~50% flat** (full dump) |
| meteor | **175%** at L1 → 38% | **~50% flat** |
| blast | 49% → 10% (decaying) | **~27% flat** |

`ABILITY_WEIGHTS` is now the design statement AND the measurement: a weight of 0.22 means
"this takes a fifth of a normal monster", which is exactly what `-- ability_hp` reports.

**Three faults were found by measuring after each change rather than at the end:**
- *cleave and blast were given weights but their damage code was never converted.*
  `ABILITY_WEIGHTS` is inert until the ability reads it. Both sat drifting while their
  converted siblings went flat — the contrast is what exposed them
- *Magic Bolt read 5-6%* — the AUDIT casting a timid 25% chip, not the ability being broken
- *Sage collapsed to 8-10% win* — a REGRESSION the anchoring introduced (below)

**Magic Bolt's spend curve was redesigned on user direction.** The old efficiency floor (0.15)
made a quarter-spend only 36% as mana-efficient as a full dump, so partial investment was
punished twice and dumping was 2.8x better. But *mages fight flocks*, so committing the whole
bar is often wrong — the curve answered the question instead of posing it, and then the flock
punished the answer. At 0.80 a quarter-spend lands 21% of a full dump rather than 9%, so
"how much do I hold back for the next one" is a real risk judgement. The old floor existed to
stop cheap chips one-shotting monsters (#70); anchoring solves that directly, so the tax was
redundant and only its side effect remained.

**A REGRESSION the anchoring caused, and nearly the wrong fix.** Wisdom's combat value arrived
through the mana pool (`base_mana = 30 + INT*3 + WIS*1.5`) because old Magic Bolt scaled with
mana SPENT. Anchoring scaled damage by the FRACTION of pool committed, silently deleting that
pathway. Sage — 1.0 Wisdom/level against 0.75 Intelligence — absorbed the whole cost and fell
to 8-10% win at elite. Sage was *already* on record as "the worst class in the game" from
measurements taken BEFORE the anchoring, so the obvious move was to buff it. **An existing
known problem is perfect camouflage for a regression you just caused.** Casters now count
Wisdom at half weight; Sage recovered to 18-23%.

**Class table after 6c** (win% — L10 normal / L30 elite / L80 elite):

| Class | L10 | L30 elite | L80 elite |
|-------|-----|-----------|-----------|
| Fighter | 88% | 45% | 61% |
| Barbarian | 90% | 45% | 38% |
| Paladin | 73% | 33% | 48% |
| Wizard | 81% | 43% | 41% |
| Sorcerer | 85% | 35% | 31% |
| **Sage** | 71% | **23%** | **18%** |
| Thief | 68% | 53% | 60% |
| Ranger | 55% | 51% | **73%** |
| Ninja | 61% | 55% | 60% |

- [ ] **Sage is still last, and it is now a real class-design issue rather than a bug.** Its
      effective caster stat growth is **1.25/level** against Wizard 1.62 and Sorcerer 1.65
      (INT + WIS×0.5), a 24% deficit that its "25% cheaper mana" passive does not repay —
      cost reduction buys more casts, but each cast is anchored, so it cannot close a damage
      gap. Either raise its INT growth, or give the passive a damage-relevant clause
- [ ] **Tricksters still lead** (51-55% at L30 elite, 60-73% at L80 against 31-48% for the
      others). Exploit was disconfirmed as the cause earlier; Outsmart's instant-win and the
      dodge advantage remain the open suspects and are still unexamined
- [ ] **L10000 spike across ALL abilities, including unconverted trickster ones** (ambush 81%).
      A spike that hits converted and unconverted alike is the final CURVE anchor being low,
      not an ability fault. Fix in the curve; do not tune abilities against it
- [ ] The `ABILITY_WEIGHTS` values are proposals. "A power strike takes a fifth of a normal
      monster" is a design opinion that wants the owner's eye, and it is now a single readable
      table rather than five formulas

**PER-SPECIES SPREAD — the same level is NOT the same fight (user challenge, 2026-09-02).**

Every audit until now reported the AGGREGATE across monster types. That hides the thing a
player actually experiences, because a player meets one monster at a time, not an average.
Measured (`-- species`, same level, same gear, 45 fights per species):

| L50 species | win% | turns | spawn% |
|-------------|------|-------|--------|
| **Titan** | **31%** | 3.0 | 2% |
| Lich | 40% | 10.9 | 2% |
| Chimaera | 48% | 4.0 | 5% |
| Young Dragon | 62% | 4.6 | 10% |
| Gryphon | 73% | 3.7 | 7% |
| Demon | 86% | 6.3 | 8% |
| Vampire | 93% | 6.6 | 8% |
| **Shrieker** | **100%** | 3.8 | 3% |

**SPREAD: 69 points.** At L1000 it is 64 points — **Hydra 22%** (40.4 turns!) to
**Demon Lord 86%**.

**This makes the aggregate numbers nearly meaningless as a description of play.** "L50 elite is
45%" is the average of a 31% fight and a 100% fight. A player who draws a Titan and a player
who draws a Shrieker are playing different games at the same level in the same gear.

**Cause: the reference model anchors STATS but not ABILITIES.** `compute_anchored_stats`
normalises HP, strength and defense, and the species `shape` multiplier is deliberately bounded
to ~2x. But monster ABILITIES are untouched by any of it, and they dominate:
- **Hydra: 22% win over 40.4 turns** — `regeneration` heals faster than the player can chew
  through, turning the fight into an endurance failure rather than a hard fight
- **Sphinx 22.8 turns, Lich 10.9** — the same pattern, milder
- **Shrieker 100%** — a monster whose kit does nothing threatening
- multi_strike, armored, ethereal, life_steal all sit outside the anchor as well

So the model made the *numbers* consistent and left the *abilities* to swing the outcome by 60+
points. That is also a likely source of the residual noise in every per-level audit: each cell
sampled a random species, so run-to-run variance was partly which monsters showed up.

- [x] **FIXED 2026-09-02 by per-species power calibration (`-- speciescal`).** Rather than
      model a dozen interacting abilities by hand, the sim measures each species' real win rate
      across three levels and all three archetypes and writes back one power multiplier.
      Targets a BAND (48-72%) not equality, and only corrects species outside it — variety is
      the point, a Hydra should still be harder than a Harpy.

      | | before | after |
      |---|--------|-------|
      | L50 spread | 69 pts (31%-100%) | **38 pts (57%-95%)** |
      | L1000 spread | 64 pts (22%-86%) | **24 pts (64%-88%)** |

      **Hydra went from 22% win over 40 turns to 64%** — the regeneration-outpaces-damage case
      that made a fight an endurance failure rather than a hard one. 29 species corrected; the
      largest were Harpy x1.70, Shrieker x1.65 and Wraith x1.64 (too easy, made harder) against
      Hydra x0.60 and Primordial Dragon x0.61 (too hard, softened).
- [ ] Residual 38-point spread at L50 is worth one more pass — the calibration ran 3 passes and
      several species were still moving. Note the verification audit measures **Fighter only**
      while the calibration used all three archetypes, so its absolute win rates read high; the
      SPREAD is the comparable number, not the level
- [ ] `regeneration` may still deserve a direct cap rather than being counterweighted by a
      blunt power multiplier — a monster that heals faster than you damage it is a bad
      experience even when the win rate says it is fair
- [ ] **`regeneration` is the standout and may deserve a direct fix first** — it converts a
      stat problem into a time problem, and a 40-turn fight is a bad experience even when won
- [ ] Re-check the residual noise in the per-level audits once species are anchored; some of
      what was blamed on sample size may be species selection
- [ ] **Playtest instructions must name real species.** `/spawnmonster Orc 50` was used for
      several manual tests and Orc has a **0% spawn rate at L50** — a tier-2 monster stretched
      up, exactly the bug that was fixed in the sim and then reproduced by hand in the manual
      test. Use the actual spawn table: at L50 that is Gryphon, Succubus, Vampire, Giant,
      Demon, Young Dragon, Chimaera

**STATE AFTER THE RESOURCE FIX (2026-09-02, n=90).** Costs are real again and the mage kit
was re-priced, and both landed harder than expected:

| Class | L30 elite before | after | L80 elite before | after |
|-------|------------------|-------|------------------|-------|
| Wizard | 43% | **66%** | 41% | **58%** |
| Sage | 23% | **45%** | 18% | **31%** |
| Sorcerer | 35% | 51% | 31% | 51% |
| Fighter | 45% | 43% | 61% | 63% |
| **Paladin** | 33% | **21%** | 48% | 40% |
| Thief | 53% | 60% | 60% | **75%** |

The mage recovery is mostly the **Magic Bolt ceiling** (`MAGIC_BOLT_FULL_SPEND_PCT = 0.20`):
the sim's mage AI spends 25% of its pool per cast, which under the old whole-pool scaling
delivered a quarter of the ability's weight. It now delivers the full weight. So a large part
of "the mage roster is weak" was the ability's spend curve, not the roster.

Roles held through the change: normal costs 32-50% against a 40% target, empowered 34-58%
against 55%.

- [ ] **Paladin is the new worst at L30 elite (21%)** and the slowest (13.3 turns at L80).
      Different class from the one that was worst an hour ago, which is a reminder that these
      rankings move whenever a shared system changes — do not tune a class until the systems
      under it have settled
- [ ] **Class spread is still 44 points** at L80 elite (Sage 31% to Thief 75%). Narrower than
      the 55 it was, still too wide
- [ ] **Turn drift at L250-L1000** (normal 12.7 and 9.2 against a 5 target; empowered 17.7).
      The HP axis is not holding in the mid-upper band even though cost is
- [ ] Re-run `-- ability_hp`: the weights were set when casts were effectively free, and a
      fight now has a real cast budget

**GEAR VARIANCE — the player-side mirror of the species spread (user question, 2026-09-02).**
Prompted by finding a *Guardian's Magical Orb of the Troll* (+60 DEF, +432 HP, +79 MP) that was
"way bigger than anything I was wearing" — +432 HP on a 652-HP character.

The simulator DOES account for items like it: `make_char` rolls gear through the real
`_generate_item` with rarity drawn from the game's own `RARITY_WEIGHTS`, fresh for every fight,
so across 90 fights it samples the whole distribution. What it does not do is *report* the
distribution. Measured, 200 builds of the same class at the same level:

| Level | min HP | median | max HP | spread |
|-------|--------|--------|--------|--------|
| L50 | 363 | 463 | 1,265 | **3.5x** |
| L250 | 1,113 | 2,017 | 5,878 | **5.3x** |

**Gear luck alone moves a character's health bar by 3.5-5x at a fixed level** — a wider swing
than the 69-point species spread, and the two multiply. A lucky player meeting a weak species
and an unlucky one meeting a Hydra are not playing the same game at the same level.

**This is probably correct for an ARPG and should not simply be "fixed".** Finding an item that
doubles your health bar is the chase, and flattening it would remove the reason to hunt loot at
all. The honest consequence is about how the balance numbers are *read*:

- [ ] **Every difficulty figure in this file describes a MEDIAN player in MEDIAN gear against a
      MEDIAN monster.** Very few real fights are all three. State that wherever the numbers are
      used to make a decision
- [ ] **Measure the tails, not just the mean.** A 10th-percentile-gear player against a
      high-difficulty species is the combination that actually generates complaints, and nothing
      currently measures it. Worth an audit that reports p10 / p50 / p90 rather than an average
- [ ] Decide whether the tails need *bounding* or merely *communicating*. Bounding item variance
      is an ARPG design change; communicating it (e.g. difficulty telegraphed per encounter) may
      be the better answer
- [ ] Note the interaction with 12b: the Phantom's whole premise is that gear and companions
      carry a player forward, so wide gear variance is the loop working — provided the floor is
      survivable

### 6f. Open after the 2026-09-02 balance session — untested and unresolved

Everything in 6/6b/6c is committed but **NOTHING is deployed**, and most client changes have
only had partial playtesting. Read this before touching combat again.

- [x] **RESOLVED: the "missing damage" fight.** A Chimaera logged 298 damage against an 82 HP
      drop. Reproduced in the sim with empowered rolls enabled and a lifesteal companion, and
      the arithmetic reconciles exactly every time (355 + 308 heal - 270 damage = 393;
      288 + 250 - 285 = 253). The player was healed by the companion's Kiss of Death mid-round.
      Damage application was correct throughout — **the LOG was wrong**, reporting the intended
      heal (428) rather than the amount actually restored (~216, clamped by missing HP), and
      never saying the heal was for the player. Fixed; the message now reads "drains N HP for
      you" with the real figure.
      **Two separate reports were being conflated**: this one (never resolved by waiting) and a
      different fight where HP updated ~4 seconds late (which did catch up). Only the second is
      a display-timing issue
- [ ] **My regression, not yet fixed: post-combat settle timing.** Gating result display on the
      beat queue means HP and resources land *after* the victory screen instead of before it.
      User: *"my health and everything dropped around 4 seconds after combat was over."* They
      later confirmed waiting for all animations still showed no drop, so there may be a second
      cause. Start here — it undermines the trust of every screenshot taken during a playtest
- [ ] **Companion durability against apex monsters.** A Chimaera dealt 298 in a round to a
      companion with 330 HP and only `sub_tier x 3%` damage reduction, so an apex monster
      one-shots a level-matched companion. `COMPANION_HP_SHARE = 0.5` is the owner's number and
      tested well at L250 against normal monsters. Whether companions should share some of the
      player's mitigation, or simply have a larger pool, is a design call and was deliberately
      NOT guessed at
- [ ] **Build the HP ledger properly.** Instrument `process_monster_turn` to accumulate every HP
      change with its cause and assert it against the actual delta. The message-parsing version
      was removed after producing confident wrong answers three times
- [ ] **Apex species still average 53% win against their 38% target.** Wraith hit the x2.50
      correction cap (it was 75% as an apex species); World Serpent and Phoenix are part-way.
      Another `-- speciescal` pass, and look at why Wraith is so easy for its tier
- [ ] Companion **ASCII art** takes a beat to reappear after combat — likely the same playback
      gating as the settle bug
- [ ] Re-run `-- ability_hp` and `-- classes`: ability weights were tuned when casts were
      effectively free, and costs are now real
- [ ] **Sage remains last** (24% caster-stat deficit its passive cannot repay) and **tricksters
      still lead**. Both are genuine class design, untouched

### 6d. Risk, reward & progression incentives
*Also split out of item 6. This is the economy around fights rather than the fights themselves.*

- [ ] **Re-measure the risk/reward table now that escape works**, then decide whether the
      1.2-9.3 level over-level payouts need raising. The `-- risk` audit models a player who
      attacks first and flees once hurt; against something far above you that first exchange is
      often fatal, so its escape column understates a player who runs on sight. Add a
      "flees immediately" mode before drawing conclusions from it
- [ ] **Should escaping COST something?** A successful flee is currently free. Dropping carried
      loot, taking a lasting wound or burning a consumable would make disengaging a real trade
      rather than a pure out. A design call, deliberately not made unilaterally
- [ ] Sample-size caveat before tuning on these numbers: 36 fights per cell, and the kill%
      column is visibly noisy (L50 read 2% at x2.0 but 13% at x3.0 — monster-selection
      variance, not a real inversion)
- [ ] **Gear acquisition must actually exist** at every level band — the loop depends on players
      having a real way to get better gear, not just on the gear existing in a table.
      **Largely owned by 12b (the Phantom)**, which is the designed answer; this line stays as
      the check that the answer covers every band

### 7. New player experience — the way the game should actually START
*User direction 2026-09-03, and MOVED UP from the bottom of the unordered "Independent" bucket
at the owner's request: "it seems like it's time to move it up."*

**Why it is placed HERE, immediately after item 6, rather than in the dungeon arc: it is the
resolution of an open balance decision, not just a UX arc.** The playtest on 2026-09-03 found
that `refcal` anchors the entire monster curve to `make_char(level, "average")` — **average gear
PLUS a companion** — while a brand-new character has neither. Measured: the reference-player
Fighter spent ~10% of its health bar per fight against a 40% target, and a gearless L5 Ranger
needs 6.2 turns to kill what kills it in 8.1. That gap is what killed four starter characters.

The output of this item is *"basic equipment, one registered companion, and a firm understanding
of the game loop"* — which is precisely **option (b) of that decision: make every new character
BE the reference player.** So building this makes item 6's low-level band correct by
construction, and no separate low-level curve is needed. The owner chose this by describing it.

**Not to be confused with 12b (The Phantom).** 12b is the *endgame outward* loop — player-built,
egg-stocked, scaling Phantoms at the edge of survivable territory. This item is the player's
FIRST Phantom, bespoke and controlled. They share vocabulary deliberately: the tutorial teaches
the loop that 12b eventually scales.

#### What already exists to build on (do not rebuild these)
- `TUTORIAL_STEPS` (client.gd ~1625) — a 7-step guided tour with `wait_for` gates
  (`continue` / `move` / `inventory_open` / `inventory_close` / `done`). This IS the "current
  guided tour" the owner refers to
- `pending_tutorial_prompt` → **Tutorial / Skip** action-bar buttons, plus
  `_toggle_disable_tutorial()`. **Skipping already exists** for the main tour — the owner's ask
  is that it exist for the NEW sanctuary tour too, and be togglable throughout
- `tutorial_hint_panel` + `_drain_new_player_modals` — first-touch hints per system, queued
- The **party system** (v0.9.738-740), which is why an NPC party member "shouldn't be that big
  of a lift" — correct, it is a party member with a server-driven action each round
- The **dungeon system**, for a bespoke short Phantom
- **Soul gems** (`character.soul_gems`) — the existing companion-registration currency, i.e.
  the "stones" the tutorial must explain how to get more of
- The **Kennel** (`persistence_manager`, 30-500 slots) — where registered companions live

#### What this REPLACES (must be removed in the same arc)
- [ ] **The free Goblin egg auto-granted on character creation** (`server.gd` ~2867). The owner:
      *"eliminate/disable the free egg/companion that new characters currently get as this
      system will replace that."* The tutorial Phantom's egg + guaranteed registration item is
      the replacement
- [ ] **The `pathfinder_1` → `pathfinder_2` → ... starter chain**, also auto-added at character
      creation (same code site). This is the current "starter quest" and the thing being
      replaced. DECISION: retire it entirely, or keep it as post-tutorial content? It is a
      gathering chain, so it teaches a different system than this arc does

#### The stages, as specified

**Stage 1 — Account creation / first login: the Sanctuary tour**
- [ ] On **account** creation (before any character exists), a guided tour of the Sanctuary,
      in the same style as the existing character tutorial
- [ ] **Skippable**, and the skip must persist. Note the Sanctuary is account-level while the
      existing tutorial is character-level, so this needs an account-level "seen/skipped" flag

**Stage 2 — First character login: the existing guided tour**
- [ ] After the Sanctuary tour and character creation, the existing `TUTORIAL_STEPS` tour plays
      on login, unless skipped or toggled off. Mostly wiring + ordering, since it exists

**Stage 3 — Tutorial quest, NPC interaction, and the inventory lesson**
- [ ] A tutorial quest with **NPC interaction and theming** (the Keeper's voice is the natural
      fit — see `docs/design/setting_bible.md`)
- [ ] Grant **a piece of gear or two**, then teach, in order: open the inventory → view an item
      → **what the stats mean** → equip it
- [ ] The "what the stats mean" step is the one with no existing surface to reuse; item
      inspection exists, a stat *explainer* does not

**Stage 4 — The first Phantom (tutorial dungeon)**
- [ ] Guided into it by quest or NPC
- [ ] **CONTROLLED: no random encounters during this stretch.** The owner is explicit — a new
      player must not be killed by a wandering spawn before finishing. Needs an encounter
      suppression flag on the character/route, which is a *new* mechanic (the player-post
      suppression floor is a different thing and is gated off)
- [ ] **Short** — "only a few monsters to speak of"
- [ ] Contains **all of their starter equipment**
- [ ] Contains **one egg**
- [ ] A **boss**, which an **NPC party member** helps kill. Reuses the party system; the NPC
      needs a simple server-side action policy each round
- [ ] The NPC ally may also have a companion (demonstrates companions in combat before the
      player owns one)

**Stage 5 — Eggs, companions, and registration (the payoff)**
- [ ] Teach **what eggs are and how to hatch them**
- [ ] A **guaranteed companion-registration item in the final Phantom chest** — or handed over
      by the NPC
- [ ] Walk through **equipping the companion**
- [ ] Walk through **checking companion stats and info** — and the owner flags this surface as
      inadequate: *"I don't think we can currently see much regarding companion stats or ways to
      compare them quickly and easily to other companions (like we can our equipment from our
      inventory at a glance)."* **This is a real sub-project, not a tooltip** — a companion
      stat/compare view with at-a-glance comparison, matching what equipment already offers
- [ ] Walk through **registering** the companion, and say plainly **what registration means**
- [ ] Explain **how a registered companion carries to a FUTURE character if this one dies** —
      this is the permadeath consolation and arguably the single most important thing a new
      player can be told about the game's shape
- [ ] Explain **how to get more soul gems** to register more companions later

**End state:** basic equipment, one registered companion, and a firm grasp of the loop.

**Stage 0 — EVERYTHING IS SKIPPABLE, including the rewards** *(owner clarification 2026-09-03)*
- [ ] The **tutorial starter quest that grants the equipment and the companion must be
      skippable too**, not just the tours. Two reasons given, and they want different handling:
      1. **A returning player bringing their own gear and registered companions.** They do not
         need the starter kit and should not be walked through equipping their first item
      2. **A player who just wants the challenge**, skipping the quest AND its rewards
- [ ] So the skip is offered per-stage, and skipping the Phantom stage forfeits its rewards
      (gear, egg, registration item) as an accepted consequence rather than a bug

**⚠ CONSEQUENCE — this partly re-opens the gear-anchor decision, and the note above it should
be read with this.** Item 7 was placed after item 6 because its output makes every new character
equal the reference player the monster curve is anchored to. **A player who skips lands back in
the gearless hole** — the one that measured 6.2 turns to kill against 8.1 to live, and killed
four starter characters. Who actually skips:

| skipper | are they geared? | verdict |
|---|---|---|
| returning player with stored gear + registered companions | **yes** | fine — they ARE the reference player by another route |
| player choosing the challenge | **no** | fine ONLY if it is an informed choice, not a hidden difficulty spike |

So the honest form of the earlier claim is: **the curve is correct by construction for players
who COMPLETE onboarding, and skipping is an explicit difficulty choice.** That is defensible,
but it means:
- [ ] The skip prompt must say plainly what is being given up — "you will start with no gear and
      no companion, and the world is sized for a character who has both". Not a bare Yes/No
- [ ] Worth deciding whether a gearless character should still be *survivable* at L1-5 (so
      skipping is hard rather than fatal), which is option (a) of the original decision. Doing
      BOTH (a) and (b) is coherent: onboarding gives you the kit, and the first few levels do
      not assume it

#### Open decisions inside this item
- [ ] Retire the Pathfinder chain, or keep it as follow-on content? (see above)
- [ ] Scope of the companion stat/compare rework — a read-only compare view, or does it also
      absorb the 6b companion-power work already open?
- [ ] Does the guaranteed starter gear come from the Phantom only, or partly at Stage 3? The
      spec says gear at Stage 3 AND "all of their starter equipment" in the Phantom

### 7b. Monster packs (a party of N meets ~N monsters)
*Renumbered from 7 on 2026-09-03 when the new-player experience took that slot. Nothing
else in this file referenced it by number.*
Last of the core combat work: packs multiply monsters per fight, so sizing them before 6 fixes
per-monster numbers guarantees a redo.

---

## ⚑ PLAYTEST 2026-09-03 (post-v0.9.741) — six findings, three of them one root cause

Owner played Warrior, Mage and Trickster out of the starter post. **Two Warriors and two
Tricksters died to gnolls.** Findings, in the order they should be fixed:

### A. The combat cards LIE about damage — one cause, most of the report

`client.gd::_estimate_ability_card_effect` is a hand-copied mirror of the server's damage
formulas. The **#6c anchoring pass converted 5 abilities** (power_strike, cleave, magic_bolt,
blast, meteor) to `bar x weight x stat_ratio` **and the mirror was never updated**, so every
converted ability's card is now wrong. Measured on a fresh gearless character
(`tools/probe/card_vs_server.gd`):

| ability | card says | server does | card/real |
|---|---|---|---|
| forcefield (L5 Wizard) | 252 | 27 | **6.0x over** |
| meteor (L5 Wizard) | 644 | 314 | **2.1x over** |
| magic_bolt (L5 Wizard) | 57 | 383 | **0.15x — 6.7x UNDER** |
| power_strike (L5 Fighter) | 51 | 125 | 0.41x under |
| cleave (L5 Fighter) | 64 | 159 | 0.40x under |
| devastate (any) | flat 5x | 3x at 1 Momentum, 7x at 5 | wrong both ways |
| shield_bash / ambush / gambit | — | — | 1.00x (still legacy, so still correct) |

The owner's exact reports reproduce: *"Field said 252 shield on the front of the card and only
gave 28"*, *"used the meteor and it only did 264 even though it said 554"*, *"did a mana bolt
for 17 and it did over 200 even though the card only showed like 20 some"*.

Note the signature: the mirror is **exactly right for every ability that was NOT converted**.
That is a partial migration, not random drift.

- [x] **DONE 2026-09-03 — the mirror no longer decides.** `combat_manager.preview_ability_effect()`
      ships in combat_state as `ability_effects` beside `ability_costs`; the client renders what
      it is told. The preview runs the REAL modifier chain rather than mirroring it again.
- [x] **DONE — Forcefield card front** corrected (it was the last surface still on `100 + INT*8`).
- [x] **DONE — drift guard.** `tools/probe/preview_drift.gd` drives the real resolve path and
      compares. Run it after touching ANY damage formula. It immediately caught three things a
      review would not have: the preview was 20% high everywhere (rank-0 mastery), Devastate's
      stamina dump makes a full bar 1.5x, and **both** mirrors still carried pre-#55 constants —
      Ambush at 3.0 against the code's 2.2, and Exploit advertising 35% of a health bar when it
      removes 22%. Those two had been lying to Tricksters since #55 with nothing to catch them.
      22 checks, 0 drift

### B. Only 5 abilities were anchored, so the CLASSES are now unbalanced against each other

The anchored model scales with the monster health bar (509 at L3, 986 at L10). The legacy model
scales with `attack` (16-23 at those levels, gearless). So a converted ability is worth **5-10x**
an unconverted one at low level. Which abilities got converted decides which class works:

| class | converted | left on legacy |
|---|---|---|
| Mage | magic_bolt, blast, meteor — **its whole damage kit** | — |
| Warrior | power_strike, cleave | shield_bash, **devastate (its finisher)** |
| Trickster | **none** | ambush, gambit, exploit(%HP), vanish |

Measured vs a same-level Gnoll, gearless (`tools/probe/starter_fight.gd`):

| L5 vs Gnoll (860 HP) | best hit | turns to kill | turns you survive |
|---|---|---|---|
| Wizard | 372 | **2.3** | 11.3 |
| Fighter | 174 (Devastate at 5 Momentum — 5 turns to build) | 4.9 | 13.6 |
| Ranger | 75 | **11.5** | **8.1** |

**The Trickster mathematically cannot win a straight fight** — it needs 11.5 turns and survives
8.1, and it gets worse with level (L8: 16.4 turns to kill, 5.9 to live). That is precisely the
owner's report: *"I attempted to take down the gnoll with just abilities and not using the
Outsmart but ultimately didn't have the damage to do so and died."*

Also note a **basic attack does 8-21 against a 631-1239 HP monster** — 40-150 turns. Basic
attacks are no longer a way to kill anything; the monster curve is calibrated against a player
who uses anchored abilities.

- [ ] **Decide the model, then convert every damage ability to it** (owner direction needed).
      Half-converted is the current state and it is the worst one

### C. Read (Trickster) is dead past ~2 stacks

`READ_OUTSMART_PER = 15` per stack, `COMBO_MAX = 5`, so the code comments promise "+75%". But
`max_chance = 48 - monster_int/3` — **~46 for a gnoll**. From a ~27% base, stack 1 takes you to
42%, stack 2 hits the cap, and **stacks 3-5 do literally nothing**. Owner: *"it seemed to cap at
around 46% making me wonder why I should even continue building stacks."* He is exactly right.

Two passes are fighting: the v0.9.698 Read engine (+15/stack, "Read is what makes Outsmart
reliable") and the #55 anti-abuse cap (48%, "Outsmart must stay a coinflip"). Both cannot be true.

- [ ] Needs a design decision, not a number tweak: either Read raises the CAP, or stacks past
      the cap buy something else (damage, a guaranteed retry, cost reduction)

### D. Outsmart spends 60% of your energy without asking

`OUTSMART_DUMP_PCT = 0.6` auto-spends 60% of current energy for up to +15% chance, and only
tells you *after* it happened. Owner: *"If we are going to have a cost on outsmart or allow
energy to be used to increase the chance the player should have a say in that or it should be
clear, not just a hidden thing that happens."*

- [ ] Make it a choice (a spend prompt like the other variable-cost cards) or at minimum put it
      on the card face. Note the card currently shows Outsmart's cost as nothing

### E. Phantom Strike does not crit

Card: *"your next attack is a **guaranteed critical hit**."* Code (`combat_manager` ~1859-1875):
`vanished` makes the attack **bypass the hit roll** and multiply damage by **1.5**, but it never
sets `is_crit`, so nothing reports a crit — matching the owner's report. Numerically 1.5x is a
crit's multiplier, so this may be only a labelling defect, but the card promises a mechanic the
code does not implement (and a natural crit would stack to 2.25x, which may be unintended).

- [ ] Decide: make it a real crit (flag it, let crit-damage bonuses apply) or reword the card

### F. Gambit is dominated

Owner: *"Gambit seems like a poor choice vs other options since it doesn't do enough damage to
risk hurting myself."* Measured: Gambit 4.5x attack = **107 at L5**, against Exploit's ~15% of
enemy max HP = **~130** with no self-damage risk. Gambit is strictly worse before the downside
is even counted.

- [ ] Falls out of B — if Trickster damage is anchored, re-weight Gambit as the high-variance
      option it is meant to be

---

## ⚑ POST-COMBAT HP STALENESS — root cause FOUND (2026-09-03)

Reported again, with the detail that cracks it: *"If combat actions are performed too fast it's
possible for a player to finish the combat before HP bars are properly updated. They typically
move or take an action pretty quickly after combat and this results in their HP bar going down."*

**Cause.** Combat results are deliberately HELD behind the playback queue so they land in step
with the log. The code that APPLIES them is the empty-branch of `_drain_combat_queue`. But
`combat_msg_queue.clear()` is called from **five** places (dismiss, dungeon dismiss,
`acknowledge_continue`, death, permadeath) and every one of them **skips that settle**. Each
carries the identical comment:

> *"Clearing the queue skips `_drain_combat_queue`'s empty handler, which is what applies
> deferred bar updates — drop the pending companion value with it..."*

They drop `_pending_companion_hp` and **never apply the deferred player HP at all**. So the bar
keeps the pre-fight number until the next unrelated `character_update` — which arrives when the
player moves. Hence "it drops after I walk."

Five copies of a comment explaining that clearing skips the settle is the tell. This is the same
"HOLD means discard" defect fixed for the companion bar in v0.9.741 (89c3960) — fixed there,
missed here.

- [x] **DONE 2026-09-03 — `_settle_combat_bars()`**, called by the drain-empty branch AND all
      five clear sites. Not a sixth guard. NEEDS A LIVE CONFIRMATION from the owner: the symptom
      is timing-dependent and the previous three attempts at this each looked right in code

---

## ⚑ QUESTS — owner observations 2026-09-03 (NOT to be worked now; slot into the dungeon arc)

Recorded at the owner's request, to be picked up when the ordering reaches quests (items 9-12).

1. **Direction/distance changes after accepting.** Very likely by design and badly communicated:
   the quest board shows a hint for an EXISTING dungeon, but accepting **creates a personal
   instance** (`player_dungeon_instances[peer][quest_id]`, server.gd ~18722-18762) at a new
   location — the description even says *"A personal dungeon will be created for you nearby when
   you accept."* So the pre-accept direction cannot be the dungeon you actually get. Confirm,
   then either show no direction until accept, or show the instance's.
2. **"Walk into any dungeon and you'll be routed to the right one" — with several such quests
   active, which one wins?** Instances are keyed per quest so the DATA does not collide, but the
   entry-time selection rule needs checking. Owner: *"Are some quests overwriting or breaking
   others?"* Answer this before touching quest content.

## ⚑ POST-CONVERSION RE-CALIBRATION — 2026-09-03 (refcal then rolecal, in that order)

Every damage ability is now on the anchored model, which made the player materially stronger and
invalidated the monster curve by the standing rule. `refcal` + `rolecal` re-run. Read-only
audits (`roles`, `classes`) below. **Everything measured before this point is stale.**

### Normals landed on target

| level | turns (target 5.0) | HP cost (target 40%) | win |
|---|---|---|---|
| 1 | 5.8 | 40% | 79% |
| 10 | 5.1 | 46% | 71% |
| 50 | 5.2 | 42% | 82% |
| 250 | 4.7 | 44% | 76% |
| 1000 | 3.9 | 35% | 84% |
| 5000 | 2.6 | 42% | 82% |

Good through L250. The old **post-L1000 slide is still visible** in turns (3.9 then 2.6 against a
target of 5.0) even though the cost axis holds — the fight gets shorter, not easier.

### Elites and bosses hit their DANGER target by getting sharper, not longer

| role | turns | target | HP cost | target | win |
|---|---|---|---|---|---|
| empowered L10 | 5.6 | 7.0 | 76% | 55% | 35% |
| elite L10 | 5.3 | 9.0 | 86% | 65% | **23%** |
| elite L50 | 3.7 | 9.0 | 85% | 65% | 30% |
| boss L1 | 6.0 | 14.0 | 89% | 80% | **12%** |
| boss L10 | 5.3 | 14.0 | 91% | 80% | **10%** |
| boss L50 | 4.8 | 14.0 | 85% | 80% | 20% |

**This is the open "length is not calibrated" item biting.** The calibrator converges on ONE
axis (a deliberate choice — see 6g, where two axes fought each other), and it reaches its cost
target by making elites and bosses *hit harder in a five-turn fight* rather than *last fourteen
turns*. Player damage just went up across the board, so fights got shorter still, and the danger
had to arrive faster to hit the same cost.

Consequence: **boss win rate at L1-L10 is 10-12%.** The owner previously accepted 18-46% with
*"companions and gear will make up the difference"* — 10% is below what was accepted, and it is
a burst-damage problem, not a difficulty preference.

- [x] ~~**DECISION NEEDED: split the role multipliers onto two axes**~~ **RETRACTED — see the
      CORRECTION section below. The length problem was an instrument artifact and this fix has
      a documented failure mode.** Original text kept for the record:
- [ ] ~~split the role multipliers onto two axes~~ — HP for length, STR for
      danger — so an elite is a LONGER fight at its target cost rather than a shorter, sharper
      one. This is the honest fix and it is what the target table has always said it wanted
      (9 turns for an elite, 14 for a boss). Do NOT tune win rates directly; that is the symptom

### Tricksters now dominate elites, by design and possibly too well

`classes` audit (60 fights/cell, average gear):

| class | L10 normal | L30 elite | L80 elite |
|---|---|---|---|
| Fighter / Barbarian / Paladin | 76 / 76 / 66% | 21 / 15 / 11% | 28 / 16 / 21% |
| Wizard / Sorcerer / Sage | 78 / 80 / 80% | 20 / 23 / 15% | 20 / 23 / 25% |
| Thief / Ranger / Ninja | 58 / 58 / 55% | **50 / 28 / 41%** | **53 / 55 / 50%** |

Tricksters are now the WEAKEST against normals (55-58%) and the STRONGEST against elites by a
wide margin (50-55% against 11-28%). That is the stated identity working — *"kill enemies BIGGER
than the warrior or mage can"* — and it is a direct, expected consequence of Read raising the
Outsmart cap, because Outsmart bypasses the health bar entirely and elite HP is what makes
elites hard.

- [ ] **DECISION: is the reach supposed to cross ROLE or only LEVEL?** The identity as written
      is about fighting things *above your level*. Outsmart currently ignores the elite/boss HP
      multiplier as well, which is a second, unstated kind of reach. Narrowing it (an Outsmart
      penalty per role tier, so an elite is genuinely harder to trick) would keep the level
      reach and remove the role reach. Recommend this over nerfing Read, which was just fixed
- [ ] **Paladin is the worst class at every row measured** (66% normal, 11% L30 elite) — was
      already flagged as "the new worst" after the resource pass. Its own item under 6c

### What is NOT stale

The card previews: `preview_ability_effect` reads the live curve, and the drift guard was
re-run after the calibration. 22 checks, 0 drift.

## ⚑ CORRECTION — "elite/boss fights are too short" was an INSTRUMENT ARTIFACT (2026-09-03)

**Retracted, and worth reading before anyone acts on a fight-length number again.**

Earlier this session I reported that elites and bosses hit their danger target "by getting
sharper, not longer" — a 5.3-turn elite against a 9-turn target — and recommended splitting the
role multipliers onto two axes to fix it. The owner approved conditionally: *"as long as this is
well documented and isn't likely to cause us more future problems."*

That condition is what saved it. Checking the history first (a9e3545) showed two-axis
calibration had already been tried and reverted, because **turns and cost are coupled through
the win rate**: raise HP to lengthen a fight, cost rises, the player dies sooner, the measured
fight shortens. `hp_mult` ran away to 305x from 11.6x. So the recommended fix had a documented
failure mode — and then the measurement turned out not to need fixing at all.

`_fight_stats_at` already had an unbiased length metric, `eff_turns` (turns extrapolated to
completion at the rate the player was actually chewing through the monster — every fight
contributes, none is selected for). The role audit simply never printed it. Now it does:

| role | turns(obs) | **eff** | target |
|---|---|---|---|
| normal L10 | 4.9 | **6.1** | 5.0 |
| elite L10 | 4.8 | **12.0** | 9.0 |
| elite L50 | 3.7 | **10.5** | 9.0 |
| boss L10 | 4.6 | **21.4** | 14.0 |
| boss L50 | 5.3 | **19.1** | 14.0 |

**Fight length is on target or ABOVE it.** An elite at L10 is a ~12-turn fight, not a 5-turn
one; a boss is ~21 against a target of 14. The `turns(obs)` column is truncated by death — at a
17% elite win rate the mean is dominated by short losses — so it reads short exactly where the
monster is strong. Acting on it would have made monsters even beefier: the runaway again.

### What the real problem is

The COST axis, and it has the same disease.

| role | HP cost | target | win |
|---|---|---|---|
| elite L10 | 91% | 65% | 17% |
| boss L10 | 97% | 80% | **7%** |
| boss L50 | 96% | 80% | 15% |

Cost is measured across all fights, and **a dead player has spent 100% of their bar**. So at a
7% win rate the measured cost is pinned near 100% almost by definition — "cost 97%" and "win 7%"
are the same fact stated twice. The calibrator cannot drive cost to 80% while the win rate is
low, because deaths peg the metric. That is why `rolecal` does not converge at L1-L50.

- [ ] **RECOMMENDED (replaces the two-axis proposal): calibrate the role multipliers against a
      WIN-RATE target instead of a cost target.** Win rate is not truncated, not saturated, and
      is the language the design decisions are actually made in — the owner's own sign-off was
      *"I'm okay with the bosses currently"* about win rates, not about cost percentages. Still
      SINGLE-AXIS, so it cannot oscillate; it just replaces a saturating metric with a
      well-behaved one. Low risk, and it directly addresses the 7% boss
- [ ] Do NOT split onto two axes. Documented failure, and the problem it was meant to solve
      does not exist
- [ ] `normal` L50 is an outlier: 59% cost against a 40% target, 64% win. Worth a look after
      the metric change

### A second instrument defect found on the way

`make_monster` in the simulator applied role MULTIPLIERS but never set the role FLAGS
(`is_elite` / `is_boss` / `is_empowered`). Every audit was fighting a monster with elite numbers
and normal flags, so anything the game keys off the flag rather than the stat line was invisible:
the new Outsmart role penalty measured as having no effect whatsoever, and boss-only damage
bonuses, empowered-mod handling and role-gated loot were all being measured against the wrong
monster. Fixed.

That makes **seven** instrument defects in two days. The rule holds: check what a number is
measuring before believing it, and check it again before acting on it.

## ⚑ Outsmart role penalty — landed, partially (owner direction 2026-09-03)

Owner's call: the Trickster's reach should cross **level, not role**. `OUTSMART_ROLE_PENALTY`
(empowered 10 / elite 22 / boss 35) now comes off the odds, sized to the share of a role's
difficulty that lives in the health bar Outsmart would otherwise skip.

It had to be taken off the **ceiling** as well as the raw chance — subtracting it from the raw
alone did nothing at high Read, because the cap was what actually bound (Ninja vs an L80 elite
did not move, and drifted UP to 66%). Same shape as the Read-cap bug fixed an hour earlier: a
term that only touches a value the cap overrides is a term with no effect.

Measured (60 fights/cell): L30 elite tricksters 50/28/41% → **38/26/31%** against 11-23% for
everyone else. L80 elite 53/55/50% → **53/53/50%**, against 20-28%.

- [x] ~~L80 elite gap is caused by RETRIES~~ **WRONG — measured at 0.5-0.8 Outsmart attempts
      per fight, so retry-spam never happens; the low health bar already prevents it. See the
      fallback-audit section below. The real mechanism is that ONE Outsmart is worth a whole
      fight of damage, and the fix was the RAMP (owner's proposal), not the falloff.**
## ⚑ "DOES A WIN RATE MEAN THE SAME THING FOR EVERY CLASS?" — no. (owner, 2026-09-03)

Three questions from the owner, all of them about the instrument rather than the balance, and
all three were right to ask. New audit: `-- fallback`.

### 1. Trickster HP was already reduced, so does that self-limit the retries? YES

Durability at **average gear** (the divisor behind every `cost%` figure ever quoted):

| class | L30 maxHP | L80 maxHP | vs Fighter (L30) |
|---|---|---|---|
| Fighter | 596 | 1020 | 100% |
| Paladin | 481 | 1274 | 103% |
| Wizard | 279 | 1625 | 60% |
| Thief | 264 | 714 | 51% |
| **Ranger** | **229** | **720** | **26%** |
| Ninja | 224 | 1186 | 69% |

And the measured **Outsmart attempts per fight: 0.5-0.8.** Less than one.

**So my earlier "cumulative retries over a long fight" theory was WRONG.** Retry-spam is not
happening and the low health bar is exactly why — the Trickster does not live long enough to
take a second and third shot. The owner's instinct was correct and mine was a guess.

The real mechanism is simpler: **ONE Outsmart at ~45% is worth an entire fight of damage.**
That is what made tricksters dominate elites, not stacking attempts. Which means the retry
falloff was the wrong lever and the RAMP is the right one.

### 2. The owner's fix — Read to 8 stacks instead of 5 — is the correct lever. DONE

`COMBO_MAX` 5 → 8, with `READ_OUTSMART_PER` 15 → 9 and `READ_CAP_PER` 5.0 → 3.125 so **eight
stacks reach exactly the ceiling five used to** (measured 72% against 71%). The Trickster now
spends more turns earning its shot, and on half a Fighter's health bar it may not survive to
get there — which is the intended tension rather than an imposed nerf.

Measured effect on elite win rate (60 fights/cell):

| | before Read fix | after cap raise | after role penalty | **after 8-stack ramp** |
|---|---|---|---|---|
| L30 elite (Thief/Ranger/Ninja) | 50/28/41% | 50/28/41% | 38/26/31% | **26/25/26%** |
| L80 elite | 53/55/50% | 53/55/50% | 53/53/50% | **48/38/51%** |
| others, for comparison | 11-23% | 11-23% | 11-23% | 11-28% |

**L30 elite is now in band.** L80 elite is still a ~20-point gap for Thief and Ninja. Stopping
here rather than tuning a fourth time against a 60-fight sample — the trend is right and this
wants a playtest, not another pass.

### 3. "Do other classes have the same problem, and are win rates / HP costs accounting for it?"

**They all have the same fallback, they all lean on it heavily, and NO, none of the numbers
account for it.** `roles` and `classes` fight to the death — nobody ever disengages — so every
non-win is recorded as if the player died. L30 elite:

| | fight to death | | | may flee below 45% | | |
|---|---|---|---|---|---|---|
| class | win | died | cost | win | **escaped** | died |
| Fighter | 23% | 76% | 89% | 10% | **76%** | 13% |
| Wizard | 29% | 71% | 84% | 15% | **59%** | 25% |
| Ranger | 28% | 72% | 82% | 21% | **52%** | 26% |

L30 **boss**: Fighter fight-to-death is 7% win / 93% died / 97% cost. Let it run and it is
**1% win / 85% escaped / 13% died / 75% cost.**

Three consequences, all of which affect how every earlier figure should be read:

1. **Death rates are overstated 3-6x for every class.** The alarming "7% boss win rate" I
   reported is a fight-to-the-death artifact; a player who disengages escapes 85% of those.
2. **`cost%` is not comparable across archetypes.** A death registers as 100%, so the column
   saturates for whichever class dies most; and a Trickster's health bar is a quarter to a half
   of a Fighter's, so the same absolute hit is a far larger percentage. Two different things
   are being printed in one column. The survivors' cost is the honest figure.
3. **Allowing flee LOWERS the win rate** (Fighter 23% → 10%) because the player bails instead
   of grinding out a marginal win. So "win rate" under fight-to-death is really "win rate if
   you refuse to ever run", which no real player does.

The Trickster is *not* uniquely disadvantaged by having only flee as a fallback — everyone has
it. It is, however, **worse at using it**: at L30 elite it dies 26% of the time when trying to
disengage against the Fighter's 13%, because it hits the flee threshold sooner and has less
health to survive the failed attempts.

- [ ] **This is the strongest remaining argument for the win-rate-target calibration** proposed
      in the CORRECTION section: measure and target the outcome under a player who disengages,
      because that is the player. Fight-to-the-death is a strategy nobody uses
- [ ] Paladin remains the worst class at every row (66% / 11% / 21%) despite the highest health
      bar — its own item under 6c
- [ ] Ranger's L80 maxHP (720) is far below Ninja's (1186) and Thief's (714) is too — the
      trickster health bars are inconsistent with each other, not just with other archetypes
## ⚑ PLAYTEST 2026-09-03 (second session, L5 Fighter) — three findings

### A. XP requirement was frozen at 100 — a LIVE bug, worse than it looked

Owner: *"This character started Level 5 needing 100 total xp to level is that right?"* No. It
should be ~2576.

`experience_to_next_level` was set **only** inside `add_experience()`'s level-up loop.
`level_up()` — the function that actually increments `level` — never touched it, and the field
defaults to 100 (the L1 requirement). So every route to a new level that does not go through
`add_experience` left the requirement frozen.

Three routes did, and **one is live gameplay**:

| route | consequence |
|---|---|
| **PARTY COMBAT XP** (`combat_manager` ~11045) | hand-rolls its own level-up loop calling `level_up()`, so **partying freezes your XP requirement at whatever it last was, permanently** |
| `/setlevel` (`server.gd` ~37279) | admin-levelled characters need 100/level |
| the balance fixture | how it was spotted |

Party play is the headline feature of v0.9.738-740, so this has been shipped and live. Visible
in the playtest log: the fixture went L5 → L6 after **two** Gnoll kills, then took ~15 fights
for the next level once `add_experience` had corrected the field.

The comment above `level_up()` asserted *"the live requirement is set in level_up()"* — it was
not, and that wrong comment is presumably why nobody looked there.

- [x] **FIXED at the source.** `level_up()` now maintains the field, and both paths call one
      shared `xp_required_for_next_level()`. Same two-paths-one-field shape as
      [[feedback-two-paths-read-same-field]]; a dead third formula was removed for this exact
      reason on 2026-09-02

### B. The difficulty curve assumes GEAR AND A COMPANION a new character does not have

**This is what killed the four starter characters, and it is the most important thing in the
session.** From the owner's own playtest log, an L5-6 Fighter built as the *reference player*
(6/7 gear, tier-appropriate companion) against the Gnolls it actually met:

| fights | mean HP cost | target | turns |
|---|---|---|---|
| 16 | **~10%** | 40% | 4-8 |

Four times cheaper than designed. But `refcal` anchors the whole monster curve to
`make_char(level, "average", klass)` — **average gear plus a companion**. A brand-new character
has neither, and the gearless measurement from earlier the same day showed the other end of it:

| L5 gearless vs same-level Gnoll | turns to kill | turns survived |
|---|---|---|
| Fighter | 5.6 | 13.6 |
| Wizard | 5.8 | 11.3 |
| Ranger | 6.2 | **8.1** |

So the same monster is trivial for the reference player and lethal for a fresh one. The owner
predicted exactly this shape: *"likely gear after abilities are properly balanced."*

- [x] **DECIDED 2026-09-03 — option (b), via item 7.** The owner's new-player-experience design
      ends with the player holding *"basic equipment, one registered companion, and a firm
      understanding of the game loop"* — i.e. every new character finishes onboarding AS the
      reference player the curve is anchored to. So the low-level band becomes correct by
      construction and no separate curve is needed. **Item 7 is therefore a balance dependency,
      not only a UX arc**, which is why it now sits directly after item 6.
- [ ] **QUALIFIED 2026-09-03 (same day):** the owner then specified that the gear/companion
      quest must be **skippable**, so "correct by construction" holds only for players who
      COMPLETE onboarding. A skipper is back in the gearless case. Either the skip prompt makes
      that an informed difficulty choice, or the L1-5 band is also made survivable gearless
      (original option (a)) — the two are compatible and doing both is the safer answer. See
      Stage 0 under item 7.
- [ ] Related: the L5 spawn table lists **Skeleton at 18.5% and it is an APEX species** —
      deliberately tuned to a 28-48% win band. Nearly one in five of a new player's first
      fights is a monster designed to beat them. Apex at tier 1 may be too early; the design
      intent ("a recognisable careful-of-that-one at every stage") does not obviously apply
      before the player has gear, knowledge, or a reliable escape
- [ ] Monsters near the starter post spawn at L1-L2 against a L5 player (post-anchored level
      pockets), which softens the above but was not the condition the deaths happened in

### C. Monster ASCII art missing on one Gnoll fight — NOT diagnosed, do not guess again

Owner: *"I had a fight with a gnoll where the ASCII art didn't display at all. It still said I
was fighting a gnoll but I couldn't see the monster."*

Ruled out so far:
- **Not missing art data.** `art_map["Gnoll"]` exists, and the lookup has an exact match, a
  VARIANT match, and a partial-match fallback before it can return ""
- **Not the empowered prefix.** The log shows "Frenzied Gnoll" that session, but `base_name` is
  stamped as the unprefixed species (`monster_database` ~1759) and the client looks art up by
  `monster_base_name`
- **Not a missing `use_client_art` flag.** All ten `combat_start` senders set it, as do the
  party and watcher paths

That exhausts the cheap theories, which by the standing rule means the next step is a
diagnostic, not a fourth guess: log the resolved art name and the returned art LENGTH at the
render site, then reproduce. Intermittent, so it wants the instrument in place first.

## ⚑ DESIGN PROPOSAL (owner 2026-09-03): gate input on animation, with a player-set speed

Owner: *"we shouldn't allow players next actions to go through until the prior one completes all
the animations and health bar adjustments... add a little arrow that can be clicked to speed up
how fast those animations and adjustments go (and one to slow them down)... remember it and stay
there until they adjust again. It should work for party play as well (maybe a vote before
increase or slowing down)."*

**This is the structural retirement of an entire bug class and should be treated as such.**
Every one of these came from the player being allowed to outrun the playback queue: the
post-combat HP staleness (three failed fixes, five code paths discarding held state), the
companion HP bar showing a stale number, buff effects appearing a beat late, the victory card
landing over unsettled bars, and a stale Continue button over a live battle. The current design
races the animation and then patches each place the race is lost. Gating input removes the race.

It also directly answers the reason the current pacing exists at all: results are held back so
they land in step with the log, which is only coherent if the player cannot act in the meantime.

Design notes for when it is built:
- The speed control is what makes gating acceptable — without it, gating is just "the game is
  slower now". With it, an impatient player sets 3x and a new player sets 0.5x
- Persist per account, not per character
- Party: the pacing is shared, so the setting has to be too. A vote is one answer; simplest
  correct alternative is that the SLOWEST member's setting wins (nobody is ever rushed past
  something they cannot read), with the leader able to override
- The existing `_combat_ui_busy()` / `_combat_playback_active()` state is already the "is
  playback running" predicate, so the gate has a natural home
- `_settle_combat_bars()` (2026-09-03) stays regardless — it is the correctness backstop for
  paths that end playback early, e.g. death

- [ ] Sits naturally with backlog item 6e (solo combat presentation). Should be scoped after
      the current balance pass lands, since it touches every combat input path
## ⚑ PARTY-PARITY AUDIT of every fix from this session (owner ask, 2026-09-03)

Owner: *"It might be worth making sure our prior fixes over this session and the last few are
fixed for party play as well if need be."* Correct instinct — three of them were solo-only.

### Already covered — the live party path reuses the shared code
No action needed on these, and the reason is architectural: the live co-op path builds a
combat-shaped *view* from `member_states` and calls the SAME functions solo does
(`process_attack(view)` at ~10193, `_process_*_ability(adapter, ...)` at ~10560).

| fix | why it already applies |
|---|---|
| Anchored ability damage (all 10 abilities), Devastate×Momentum, Forcefield anchor | shared `_process_*_ability` via the adapter |
| Phantom Strike reports a crit | shared `process_attack(view)`; the view carries `vanished` |
| `_settle_combat_bars()` HP staleness | it was extracted from code that already handled `_pending_party_end_character` / `_pending_party_my_state` / `_pending_party_final_state` |
| **XP requirement frozen at 100** | the party XP loop was the *cause*; fixing `level_up()` fixed party first |
| Hunter's Mark bracket escape | `combat_scene_panel`, shared by both |
| `last_ability_amounts` prefill | shared client popup |
| Missing-art diagnostic | shared `monster_art` |

### Was solo-only — FIXED
- [x] **Authoritative card numbers.** `ability_costs` (v0.9.741), `ability_effects` and
      `turn_regen` were added to the solo `get_combat_state()` only, so **a player in a party
      still saw the client's own estimates** — the ones measured wrong by 0.15x to 6.0x. Co-op
      is the headline feature, so "we fixed the lying cards" was true for half the game. Now
      built per-member in `_party_member_hand_payload` (which is per-recipient, the right
      channel) from a member view, and read by `_apply_party_hand_from_message`
- [x] **Role flags.** `is_apex_species` / `is_elite` / `is_empowered` reached the solo state
      only, so a party fight never showed the red apex tag. Added to `_party_combat_snapshot`
- [x] **Chain engine carry is now ONE definition.** `chain_engine_carry()` holds the rule
      (Momentum and Focus full, Read halved) and both `end_combat` and `_end_party_combat` call
      it. Party combat does **not** chain flocks today, so nothing consumes the party snapshot
      yet — it is written so that when party flocks are wired the carry is already correct
      instead of silently defaulting to a full, un-decayed Read

### Found: Outsmart does not exist in party combat, so Read is INERT in co-op
The live party command handler accepts only `attack`, `flee` and `ability` — "outsmart" falls
through to *"Unknown combat command."* And `_party_member_hand_payload` hardcodes
`outsmart_chance = 0` with the comment *"charge viz not wired for co-op yet"*.

So a Trickster in a party builds Read and **it does nothing at all** — its entire class engine
has no payoff in co-op. Everything done to Read today (the cap raise, the 8-stack ramp, the role
penalty, the halved chain carry) applies only to solo play.

- [ ] **DECISION: should Outsmart work in a party?** It is an instant win on a shared monster,
      so it is not a straight port — one member could end a fight the whole party is in, which
      raises reward-splitting and consent questions the solo version never had. Options: enable
      it as-is, enable at reduced odds, or give the Trickster a different co-op payoff for Read.
      Until then a Trickster is playing a party fight with one third of its kit switched off

### Hazard: three `_party_*` fossils are DEAD CODE carrying stale formulas
`process_party_combat_action()` has **no callers**, which makes `_party_process_attack()` and
`_party_process_outsmart()` unreachable too. They are dangerous because they read as
authoritative and are badly out of date — `_party_process_outsmart` computes
`clamp(30 + (wits - monster_int) * 2, 5, 75)`, which ignores Read, class, level difference, the
attempt falloff and the role penalty, and caps at **75%** against solo's 48%. I nearly reported
that as a live balance hole before checking whether anything called it.

- [ ] Delete all three, or rewrite them to delegate to the shared path if the intent was to keep
      a second entry point. Leaving a stale duplicate of a formula next to the real one is the
      exact shape that produced the lying cards
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
- [ ] Existing threads this will likely absorb or supersede: the UX revamp arc and the
      unspent-stat-point nudge. **NOT the tutorial/starter-quest thread — that became item 7
      (new player experience) on 2026-09-03 and is being built, not audited.** An onboarding
      audit run after item 7 lands is still worth having

## Independent — slot in any time (no dependencies)
- [ ] Card market live list-to-buy smoke test (built, never exercised end to end)
- [ ] Launcher revamp + in-game feedback inbox
- [ ] UI-scale registration for remaining elements (action bar, inventory, market, crafting...)
- [ ] Unspent stat-point "+" badge (players forget they have points)
- [ ] Combat default layout at 1080p (cards overlap the monster art)
- [ ] Companion cosmetics: ASCII border + shadow layer (data layer already shipped)
- [ ] Merchant/market **baseline NPC stock** — merchants only equalise player listings, so
      off-circuit posts stay bare
- [x] ~~Tutorial + starter quest chains for a zero-gear character~~ — **promoted to item 7**
      (new player experience) on 2026-09-03. Do not track it here as well; that is how the
      Dungeon Atlas ended up as three tasks in three places
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
- **⚑ RE-CALIBRATE AFTER ANY PLAYER-SIDE CHANGE.** Monster stats are derived from a REFERENCE
  PLAYER (`shared/reference_monster_curve.json`, built by the sim's `-- refcal`). Anything that
  makes the player stronger or weaker — gear, companions, abilities, resources, classes, races,
  the `make_char` model itself — silently invalidates that curve, because the monsters were
  sized against the old player. This has already happened twice: the gear calibration, and the
  companion HP rework (which pushed elite-at-L1 to 90% win against a 70% target). It is not a
  bug in the design; it is the cost of anchoring monsters to the player, and it is the right
  trade. **The rule: after a player-side balance change, run `-- refcal` (2-3 passes), then
  `-- roles` to confirm, and treat every number measured in between as stale.**

---

## Recently shipped
- **2026-09-02 (site + docs, no client build)** — website refresh live: setting-led copy that
  explains the name, real in-game screenshots, accuracy fixes (Linux support, party of 5,
  deck-driven combat). Setting bible revised to a single cause. Screenshot capture harness added

- **v0.9.741** — THE BALANCE PASS: every monster resized against a reference player at every
  level (the mid-game hump and the post-L1000 slide are gone), apex species (15 deliberately
  dangerous species, 2x XP / 3x drops, tagged ☠ [APEX] in combat), elite/boss/empowered roles
  calibrated (empowered was harder than elite), regeneration capped (a regenerating boss was
  mathematically unwinnable), Forcefield anchored to the health bar (it was absorbing >1 full
  bar per cast — immunity with a mana cost) + its lying description fixed, companion HP scaled
  by aggro and companion damage/defense/regen unflattened, per-hit aggro rolls, server-authoritative
  ability costs shown on cards, mage kit anchored to the health bar (Bolt/Blast/Cleave) + Wisdom's
  caster damage restored, escape priced by level RATIO with a 25% floor, flocks budgeted per
  encounter, solo combat given the co-op playback pass, XP-remaining label fix

- **v0.9.740** — party leadership rotation + duplicated rewards, follower/post rules, party of 5,
  buff + item targeting (teammates and their companions), co-op playback pacing (rounds play fast
  but complete; Continue skips *to* the rewards), Forcefield/Haste co-op fixes
- **v0.9.739** — co-op combat you can follow (one animation clock), party items, party permadeath,
  login sprite offset, relog full-heal fix, 2-client test harness (`tools/test_setup/`)
- **v0.9.738** — real co-op party combat (shared fight, party cards, per-actor playback)
- **v0.9.735** — card arc: dungeon-exclusive cards, card market, class roster pass, FPS cap
