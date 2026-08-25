# Dungeon Revamp — Master Design (task #31)

Planning doc. Full user brainstorm captured 2026-08-25. Design-first — this is the
agreed VISION; slices/sequencing still being decided. Theme sub-system detail lives in
`dungeon_themes.md`.

## Current state (baseline we're changing)
- 40+ dungeon TYPES (T1–T9), each a fixed identity (one monster type + one boss).
- A run = 3–10 BSP-grid floors walked under a STEP BUDGET, hitting encounter/treasure/
  trap tiles, ending at a boss + guaranteed boss egg. Every instance is IDENTICAL.
- Player STAYS on the overworld 'D' tile while inside → blocks others from entering.
- Dungeon view is fairly zoomed-OUT (player sees a lot of the floor).
- Rewards: boss egg (always same creature), materials, a rare card, chest loot.
- Bosses = stat-inflated monster + a couple abilities; same every run.

## Design pillars
1. Every run feels different. 2. Dungeons are a REASON to play (farm HERE for THIS).
3. Meaningful choices mid-run. 4. Added danger is opt-in / telegraphed (permadeath-safe).
5. Players react to threats (no unavoidable damage). 6. Dungeons are a place to TEAM UP.

## ⚠ HARD BALANCE CONSTRAINT — SOLO-POSSIBLE (user, 2026-08-25)
Every dungeon MUST be completable SOLO by an appropriately-levelled/geared player. Party
play is a **force multiplier / social bonus, NEVER a requirement.** This governs ALL
balance in the arc: boss HP/damage, wandering-monster pressure density, mechanical-theme
difficulty, encounter counts. When tuning for the multiplayer north star, tune the SOLO
baseline first, then let parties trivialize/speed it — do NOT balance around a full group.
Applies to the combat simulator baselines too (`tools/combat_simulator`).

---

## WORKSTREAM A — Variety & Themes  (in progress; detail in dungeon_themes.md)
- Per-run **theme**: cosmetic color/pattern baseline; RARE mechanical theme with pre-entry
  WARNING; **Catalyst** item forces/upgrades; theme → guaranteed themed egg.
- **Enemy cosmetic color/pattern** system (slice 1) — enemies currently have none.
- ✅ Slice 0 (`reapply_variant`) DONE + deployed.

## WORKSTREAM B — Loot, Progression & Discovery
- **Signature drop per dungeon:** each dungeon is farmed FOR a specific thing (a unique/
  set piece, rare material, themed companion). Makes "which dungeon?" a real decision.
- **Discovery / "what drops where" (user's open question):** players need to KNOW what a
  dungeon offers and be able to FIND it — not pure random happenstance. Proposed: a
  **Dungeon Atlas/Codex UI** (like the Bestiary) listing each dungeon type: tier/level,
  signature drop, possible themes, and known map locations. Plus map markers for
  discovered dungeons + maybe board/NPC "leads" that point you toward one that drops X.
- **Dungeon-exclusive cards (#38):** cards STRONGER than starters, farmed to use/sell/
  trade (ties to card market #39). **Theme-influenced:** a card's flavor/effect keys off
  the dungeon's monster theme (e.g. a Frostbound dungeon drops a frost-flavored card).
  Replaces today's generic "+1 copy of a favourite."
- **Risk scales reward:** deeper floors / mechanical theme / Catalyst → higher loot tier,
  guaranteed rare+, bonus card/egg.
- **Companion Tier-RANK variety (#5):** today players mostly find T1-1, T2-1, T3-1 …
  (rank 1 of each tier), leaving higher-RANK-within-a-tier content unused. Dungeons should
  offer varied sub-tiers/ranks so players hunt higher ranks of their current tier. (A
  dungeon-instance sub_tier → egg-rank change; relatively contained.)
- **Final chest as a PAYOFF beat** — proper end-of-run reveal, not a line of text.

## WORKSTREAM C — Structure & Pacing
- **Bigger & longer dungeons.** Current ones (esp. low tier) are small + run through fast.
  More floors / larger grids / more rooms.
- **Replace the STEP BUDGET with a PRESSURE mechanic (user open to this).** The step
  budget only exists to stop players camping one floor. If we let **monsters spawn/wander
  on floors over time** (see below), a forward-pressure mechanic (rising danger the longer
  you linger — more/tougher spawns, a closing threat) naturally keeps players moving
  WITHOUT an arbitrary step counter.
- **Wandering monsters (#6):** un-aggroed monsters roam the floor, creating chances to
  bump into players (and vice-versa). This IS the pressure source.
- **Branching paths / room choices (#6):** multiple routes so players can try to AVOID
  monsters, plus risk/reward forks (greedy room = better loot, more danger).
- **Special rooms:** shrine (buff), elite room (mini-boss + guaranteed drop), rest, gamble.

## WORKSTREAM D — Bosses & Encounters
- **Real boss mechanics:** phases, telegraphed big hits, summoned adds — not a stat brick.
- **Telegraph COUNTERPLAY is mandatory (user constraint #4):** a telegraphed hit only lands
  next turn unless the player responds. In our turn-based deck combat, the counterplay =
  the player's next turn: **defend/guard** (mitigate), **stun/CC** the boss (prevent), or
  **burst it down** (race). Uses existing kit (iron_skin/fortify, shield_bash/paralyze,
  finishers). Telegraph must be shown clearly in the log + battlefield so the player knows
  to react. NO unavoidable damage.
- **Mini-bosses, encounter variety** (ambushes, mixed packs, hazards), **theme empowers the
  boss** too.

## WORKSTREAM E — Presentation (zoomed-in sprite dungeon view)  #7
- **Zoom the dungeon view IN** — players should see less of the floor at once (fog/reveal).
- **Reclaim screen real estate:** use the `game_output` (chat) window area for the dungeon
  view when it's not in use → bigger, more immersive dungeon canvas.
- **Sprite-based dungeon:** use the (currently unused) per-sprite ANIMATIONS for battlers;
  represent chests/traps with unused sprites; give enemies a **uniform on-map sprite** the
  player can **hover** to see info (Level + ASCII art) — reserves the full ASCII art for
  combat / hover, keeps the map readable.

## WORKSTREAM F — Multiplayer & Party  #8 #9  (BIGGEST / most architectural)
- **Instanced dungeons:** entering a dungeon should NOT keep the player on the overworld
  'D' tile blocking others. Multiple players/parties enter the SAME dungeon type
  concurrently (separate instances, or shared instance for a party).
- **Party rewards:** party members who complete a dungeon each get rewarded.
- **Party play + NEW combat system:** the game used to have party play; it must be
  re-integrated with the deck/hand combat. Players TEAM UP for big challenges (dungeons,
  bosses). This is a major combat extension (multi-player turns, shared/So separate hands,
  aggro, downed-ally, revive?) — needs its own deep design pass.

---

## Sequencing notes (dependencies)
- **A** is in flight (slice 0 done). Enemy cosmetics (slice 1) feeds E (sprites) + A.
- **C** (bigger dungeons + wandering + pressure + branching) is a cohesive gen/movement
  rework; the wandering-monster pressure REPLACES the step budget — do them together.
- **E** (zoomed sprite view) pairs naturally with C (you're rebuilding the dungeon view
  anyway) but is a big client rendering job.
- **B** discovery/Atlas + signature drops are largely independent knowledge/loot layers.
- **D** boss mechanics can layer on any time once counterplay is confirmed.
- **F** (party/multiplayer) is the biggest and most architectural — likely its own arc.
  Instancing (#8) is a prerequisite for concurrent play; party COMBAT is a separate large
  design. F could be sequenced last, or the instancing half done earlier if blocking.

## SEQUENCING — DECIDED (user, 2026-08-25)
- **NORTH STAR = Multiplayer/party dungeons (F).** It's the headline goal; everything is
  built TOWARD team-up dungeon play. Implication: the dungeon-INSTANCE model must be
  multiplayer-aware from the start (decouple the player from the overworld 'D' tile so
  they don't block others; instances support concurrent occupants / parties). Party
  COMBAT-with-decks is its own big design, but the *instancing groundwork* should land
  early since it underpins the headline.
- **FIRST real build slice = Structure & Pacing (C)** — but designed multiplayer-aware.
- Immediate next code step BEFORE C = the already-approved **enemy cosmetics (slice 1)**
  (independent; feeds A themes + E sprites).

### Proposed Workstream C sub-slices (multiplayer-aware)
- **C0 — Instancing groundwork (multiplayer prereq).** Decouple a player-in-dungeon from
  the overworld 'D' tile so they don't block entry; let multiple players/parties occupy
  concurrent instances. NEEDS a code investigation of the current entry/occupancy model
  first (how `handle_dungeon_enter` ties the player to the tile, how instances are keyed).
- **C1 — Bigger & longer dungeons.** More floors / larger grids / more rooms; right-size
  per tier so a run builds to the boss.
- **C2 — Wandering-monster pressure (replaces step budget).** Monsters spawn/roam over
  time → forward pressure; retire the step counter.
- **C3 — Branching paths / room choices.** Multiple routes (avoid vs greedy) + special
  rooms (shrine/elite/rest/gamble).

Other workstreams (B loot/discovery, D bosses, E sprite view) layer after / alongside C;
full party COMBAT (F) is the capstone the above builds toward.
