# Phantom Badlands — Master Backlog

**The single ordered to-do list.** Read it before proposing what to work on; update it as work
lands. Items are ordered so each one's inputs are settled before it starts — working out of order
is what forces revisits.

History lives in `docs/archive/BACKLOG_journal_to_2026-09-07.md`. Search it before re-opening
anything: it records why several approaches were REJECTED, and re-proposing those is the most
common way to lose a session.

---

## ▶ NEXT SESSION — START HERE (rewritten 2026-09-11, third session of the day)

**Master is clean and pushed. Nothing is parked.** Card instances (step 1 of THE ORDER) is merged.
**Next in THE ORDER is step 4: the OVERWORLD, Phase 2.95, starting with PHASE 1** (move rendering
from the server to the client, no visual change). Sprite interiors is finished as a separate arc:
the Sanctuary is done, and NPC post interiors turned out to be overworld tiles rather than their
own screen, so they are part of Phase 2 there. Phase 1 is also the item that RAISES the player
ceiling, since it removes the most expensive per-player work the server does.

**Unreleased on master, all probed** — none of it has been played yet:
- **Card instances.** Every copy of a card is its own card (`cleave`, `cleave#2`): its own uses,
  milestone picks and effect rank; legacy `{card: count}` saves split on load with each copy
  inheriting the shared progress; the hand and deck carry copies; a sold copy takes its upgrades
  to the buyer; card listings never merge; thinning benches a copy and `+` brings it back.
  Probe `card_instances.gd` (47 checks), `card_market_roundtrip.gd` rewritten.
- **SERVER: two overworld costs, both invisible.** The tile cache (~1,390 disk stats per move
  gone) and the minimap's post bucket. Together a location update costs **15.6 ms instead of
  31.1 ms** in the real world, and the server no longer re-generates a tile it just made.
  **Needs a DEPLOY**; no client change, nothing visual — `tile_cache.gd`, `minimap_posts.gd`.
- **The overworld map as DATA** (Phase 2.95 PHASE 1). 28.2 KB a step becomes 3.4 KB, with the
  display string rebuilt on the client byte for byte. **Server deploy AND client release, and
  the old-client path is the thing to check by hand** — `map_payload.gd`, `map_payload_golden.gd`.
**THE DUNGEON ARC (2026-09-11) is all unreleased and all server-side except the last line.**
It is one arc and wants ONE deploy and one playtest, not six:
- **Dungeons stand in country that matches them.** Placement follows the land, and the GRADE is
  read off the ground rather than off the type - which is what makes an A5 Goblin Dungeon
  possible. 1,489 of 1,500 sampled spawns land inside their own level band, none further than two
  levels off. `dungeon_placement.gd`, `dungeon_grade_from_land.gd`.
- **There are 3,000 of them instead of 200**, spread over the whole world rather than the inner
  4%, at about one per 100 tiles walked. Affordable because dungeons are indexed by position: a
  map-radius query is 1.8us against 117us scanning. `dungeon_index.gd`.
- **Dungeons have a rarity.** `spawn_weight`, authored on all 53 types and read by nothing since
  it was written, now picks the type; a higher rank is rarer than a lower one in the same country.
- **A dungeon holds more than one kind of monster** - three in four its own species, the rest
  neighbours of the same grade. The boss and the guaranteed egg stay its own. `dungeon_species_mix.gd`.
- **Floor eggs follow the dungeon.** By RANK (mean 4.5 flat before, now 1.5 at rank 1 to 8.0 at
  rank 9) and by SPECIES (whatever actually spawned down there). `floor_egg_rank.gd`.
- **Dungeon markers stop building rooms nobody enters**, and say so in the log if anything ever
  reads one. `lazy_dungeon_interior.gd`.
- **Personal dungeons get cleaned up** - a 30-minute grace after their owner goes offline, a
  24-hour cap, and an immediate drop on permadeath. `personal_dungeon_cleanup.gd`.
- **COMPANIONS: a grade finally beats the grade below it.** One ladder for HP, owner bonuses,
  abilities and damage. This is a PLAYER-POWER change, so the monster curve was re-calibrated
  after it. `companion_ladder.gd`.
**What to watch in play:** the world should feel full of dungeons without feeling like wallpaper;
a dungeon's grade should match its surroundings; low-rank dungeons are now worse for eggs and
high-rank ones better; and companions at a high rank of a low grade got weaker while high-grade
ones got stronger.
- **Cosmetic VARIANTS on sprites.** A lime wolf is lime in the dungeon and on its Sanctuary
  cushion, not only in its ASCII art; eleven patterns, and the baked floor under the sprite is
  left alone — `monster_tint.gd`. Client-side, nothing to deploy.
- **The sprite SANCTUARY**, with companions on cushions, animation, the 2x player, station
  highlights and the MIRROR (account look). The mirror needs the server deploy too —
  `sanctuary_room.gd`.
- Recall on the Sanctuary companions page — `companion_recall.gd`.
- Party combat CONFIRM step, party only — `party_confirm.gd`.
- Tier level bands in one table — `tier_bands.gd`.
- Licences recorded; restricted art stays untracked.
- Help screen: 26 audited fixes, the main help page formats again (keys had shown as `[%s]`),
  gathering described as it really works — `help_topics.gd`.
- Ranger and Barbarian card faces include their engine ramp — `preview_drift.gd`.
- First-gather tutorial is sent again, rewritten for the scratch-off grid.
`docs/PLAYTEST_QUEUE.md` items 7-8 cover Recall and the confirm step. **Card instances needs a
playtest line too before release:** a character with two copies of one card, thin one, restore it,
rank one copy up and confirm only that copy shows the upgrade, list a spare at a trading post.

**Card instances, second slice (not started):** the deck screen still shows ONE tile per card
with a copy count, and the market picker lists by card and sells the least-invested copy. To
let a player choose WHICH copy to thin or sell, both need per-copy rows showing each copy's
upgrades. The server already accepts a specific copy id (`cull_ability_card`,
`market_list_card`), so this is client UI only.

**Track B note:** card instances changes player power only for decks holding extra copies (a
second copy now levels on its own instead of sharing the first's rank). Batch it with the rest of
Track B for the single chain run; do not run the chain for it alone.

**Help screen FIXED (Track A, unreleased):** all 26 audited entries corrected, and the main help
page now formats; it had shown every key binding as `[%s]`. Pinned by `tools/probe/help_topics.gd`.
Two owner questions came out of it: the dead Knight/Mentee bonuses (see Phase 3 list).

**Four owner decisions are answered (0b done)** — see THE ORDER.

**Five items are waiting on live play data now that v0.9.772 shipped** — the five characters at
L25+, the rest-change feel check, the "party play isn't working" repro, the dungeon-level mismatch
second example, and the dungeon-depth confirmation. Ask the owner whether any produced data before
re-deriving them.

**Standing rules that cost time this session when forgotten** (all now enforced by tooling, but
know why they exist):
- **Never write a player-facing stat or formula description from intuition.** Owner: *"When
  putting in stat descriptions that are meant to be our bible it's not acceptable to run off
  intuition... Making guesses is costing us time and leading to bad info (aka low quality slop)."*
  `tools/probe/stat_claims.gd` checks the claims against the code. Run it after touching any.
- **An audit written around the wrong UNIT is as wrong as a guess and far more convincing.** This
  fired three times in one session (card ids vs display names; format strings vs surfaces;
  a gate's definition vs its callers). When sweeping, enumerate the SURFACES the player sees, not
  the strings you expect them to contain.
- **Prove every fix by re-injecting the fault** and watching the probe fail. A detector that never
  fires looks exactly like one that finds nothing.

---

## Where the game is (2026-09-11)

Live: **v0.9.772** (client + launcher; no server change since v0.9.771), released 2026-09-11.
**UNSHIPPED in master: FOUR things held back deliberately, awaiting the owner at a PC** — arrow-key
diagonal movement (the 70ms chord window), cycle values, reveal upgrades, and the dungeon panel
confirmations. `docs/PLAYTEST_QUEUE.md` holds a one-command setup and a checklist for each. Do not
let any of them ride along in a release before it has been checked.

- **The dungeon reports beside the map, never over it.** Owner 2026-09-09: *"It's kind of jarring
  to take over the whole dungeon art screen with it"*, then *"Can we not do the rest and food in
  the right as well. Inventory makes sense to do the canvas but the other two probably not."*
  The old rule was "anything the player must acknowledge takes the canvas", which lumped a
  one-line notice in with a full screen of items. Now:
    * NOTICES (trap, gather result) -> `_dungeon_log`, six lines in the side panel above the key,
      cleared per floor. Each keeps its own colour, so a trap stays red and stays scannable.
    * SHORT MENUS (rest, food, gather prompt) -> `_dungeon_panel_menu`, rendered in the panel and
      replacing the log while open. Gated at RENDER time on `_dungeon_panel_menu_open()`, not on
      the buffer being non-empty, so none of the five exit paths can leave a stale menu up.
    * FULL-SCREEN MENUS (inventory, settings, admin, dungeon list) still take the canvas.
  The trap used to clear `game_output` for a `===== TRAP! =====` banner — and was silently broken
  doing it, since the ack flag that routes text to the canvas was set AFTER the five writes, so
  every one went to chat and the player got a BLANK canvas with one button. The trap's Acknowledge
  gate STAYS (owner: *"Keep it"*). `awaiting_dungeon_gather_result` deleted — nothing set it true.
  `gm_spring_trap` + the `dungeontrap` / `dungeonrest` capture scenes make both screens reachable
  on demand; the trap screen had been broken since it was written and was only ever seen because a
  screenshot run happened to walk onto one.

- **Card upgrades are no longer offered where they cannot work.** Four (`swift`, `sacrificial`,
  `vindication`, `refund`) needed damage or a kill but were marked `KIND_ANY`, so a milestone
  spent on them from a buff card was simply lost. `-- upgradefit` casts every card with and
  without every upgrade it can be offered: dead pairs 71 -> 8.
- **Four audits gate the class surfaces**: `cardaudit` (what a card SAYS), `enginenames` (meter,
  log, label), `statdesc` (stat lines), `upgradefit` (do upgrades do anything). Three PASS.
- **Read `upgradefit`'s docstring before trusting it.** It was wrong four times before it was
  right, and every wrong version produced output indistinguishable from a real finding.

- **One name and one number per thing.** A day of player reports turned out to be one shape nine
  times over: a value stated in two places, drifting. Card faces vs hovers, the Trickster meter
  tag, stat pools, racial passives (SIX copies), loot names, dungeon levels. Each was fixed at the
  precedence or the generator, not at the instance.
- **`-- namesweep`, `-- enginenames`, `-- statdesc`** cover all nine classes and fail loudly.

- **Cards tell the truth about their own damage.** The estimate counted `power` picks alone while
  nine more multipliers were applied, so four upgrades added 25-35% invisibly and Slow Burn took
  25% away with no visible change. One shared table now feeds the roller and the card face; the
  rank-up hover previews YOUR card with the pick on it. `-- upgradepreview` holds them to 0.007.
- **All nine engines have their own name** (Momentum / Rage / Conviction, Focus / Volatility /
  Insight, Leverage / Aim / Read). `-- enginenames` checks every surface, 9/9.
- **Every release now passes `tools/verify_release_build.sh`** before upload, which asserts the
  perf guards and catches the stale-export cache. v0.9.757 was the first through it.

- **All nine classes run one of three engine shapes**, one of each per archetype, with their own
  starter deck and their own card names. No two classes in a path play alike.
- **Difficulty ramps with level** (`DIFFICULTY_RAMP`): forgiving while a player learns, tightening
  as gear and skill accumulate.
- **Endgame is on target.** A best-in-slot player survives 95.6-99.1% of L100-L1000 fights against
  the owner's stated 95%. About 55% of those are outright wins and 36-42% are retreats.
- **Career survival, average gear** (`grow`, death per encounter): Fighter 0.2%, Sorcerer 0.2%,
  Wizard 0.2%, Paladin 0.3%, Grifter 0.3%, Ninja 0.7%, Barbarian 1.2%, Sage 1.3%, Ranger 1.9%.
- **Gear lockout is prevented**: `DROP_LEVEL_FLOOR_RATIO` floors item level at 75% of the player's,
  so farming below your level still yields gear near it.

---

## What "balanced" means here — read before any balance work

Owner, 2026-09-06/07. This supersedes win-rate parity, which was never the right target.

- **"Most characters die, that is the point."** Balance is not every class reaching the top.
- **AND** *"a careful player should be able to get there, with good gear, card upgrades, strong
  companion, and skilled play."* Both hold at once.
- *"Even with all of these things if a high level player isn't careful and takes on a challenge too
  great... they can still meet their end."*
- **Balanced does NOT mean equal kill speed.** Classes should feel different; players find their
  preference through playstyle.
- **95% survival** for endgame fights when playing as intended. Survival counts a RETREAT — knowing
  when to run is part of playing well.
- Fights must not get boring through **length OR lack of choices**. Never pad a fight: a turn with
  no decision only gets worse when repeated.

**The measurement consequence.** Death risk must FALL as progression accumulates; a single global
rate is the wrong model. At a CONSTANT rate the endgame is arithmetically unreachable, because a
climb to L10000 is ~177,000 encounters. Measure per stage AND per gear profile (`riskcurve`), never
as one number.

**Do not call reaching L20 "finishing the game."** It is ~0.3% of the ladder.

---

## ⚑ TWO TRACKS — the sequencing rule that decides everything below

Asked 2026-09-10: *"Looking at everything still on our backlog whats the most efficient way to
proceed?"* The answer is not an order of items. It is that **the items fall into two tracks, and
mixing them is what burns sessions.**

**Track A — art, UI, tooling.** Dungeon rooms, sprite interiors, tall props, bake generators,
UI-scale registration, the docs/help audit, the licence chores. None of it changes player power,
so **none of it invalidates the monster curve.** No calibration chain, no playtest gate, no
recalibration tax. It can ship continuously and in any order.

**Track B — cards and balance.** Card instances, the upgrade rarity weight, companion and dungeon
card passes, starter decks, the 53-card content, the per-class death-rate work. **Every one of
these invalidates the curve** (see the recalibration rule in CLAUDE.md), and the chain must be run
ONCE after all of them — running it per change costs ~25-45 minutes a round and was abandoned as
a strategy on 2026-09-04.

**So: batch ALL of Track B behind one chain run, and do Track A work in between rather than
interleaving a card tweak between two art tasks.** A single card change dropped in the middle of
art work forces a chain run that a batched approach pays once.

**Track B has one gate that must be decided before the rest of it starts:** card INSTANCES. It
reaches the save format, the deck UI, the combat hand, the milestone system and the market, and
the 53-card content pass must not begin before it — the cards are the thing that will exist in
multiples. That decision is the owner's, not a thing to infer.

**Track A has one item that is ready NOW:** dungeon rooms from the Raven packs. The pack choice is
settled by measurement, the room/corridor split needs no protocol change, and the only open
question (the seam at a doorway) needs a screenshot rather than analysis.

## How to work on balance without burning sessions

Both failed calibration chains on 2026-09-07 cost ~45 minutes each, and **neither failed because
the simulation was wrong** — it faithfully measured a broken instrument. Use the cheap audits:

| audit | ~time | answers |
|---|---|---|
| `preflight` | 2 min | **is the chain worth running?** decks are 5 cards, the two measurement paths agree, nobody idles |
| `lowlevel` | 2 min | are L1-L3 classes resource-starved or auto-attacking? |
| `riskcurve` | 4 min | death rate by level AND gear — does risk fall as you progress? |
| `endgame` | 4 min | the 95% target, at high n on the cells that decide it |
| `cardnames` / `statdesc` | instant | what each class is SHOWN about its cards and stats |
| `climbcost` | instant | encounters a climb costs, and the survival arithmetic |

**Iterate on those; run the chain ONCE at the end, gated by `preflight`.**

**A global player buff cannot fix a class gap.** The chain holds win rate at target, so any
across-the-board buff is cancelled by monsters getting stronger on the next refit. Only PER-CLASS
changes survive. Measured: a global CON mitigation buff washed out entirely on the next chain run,
while the Paladin's stat realignment held.

---

## ⚑ PLAYTEST QUEUE — `docs/PLAYTEST_QUEUE.md`

Four things are committed to master and deliberately NOT released, waiting on the owner at a PC:
arrow-key diagonal movement, cycle values, reveal upgrades, and the dungeon panel confirmations.
`docs/PLAYTEST_QUEUE.md` holds a one-command setup and a specific checklist for each — do not
re-derive them, and do not let any of it ride along in a release before it has been checked.

Two scenarios were added for it: **`cycle_cards`** (dungeon cards carrying cycle values, plus a
reveal upgrade already taken on a class card) and **`in_dungeon`** (parked on a dungeon entrance,
stocked, for the hover / chest / run-log checks).

## v0.9.772 SHIPPED (2026-09-11) -- the launcher can reach players again

Owner: *"We historically had a way for the client to download the launcher and effectively 'self
update' it without players having to reinstall the launcher from the site. Is that something we
can still do here?"*

**It was never removed. It was never switched on.** Read out of the code rather than remembered:
the capability exists TWICE — `launcher.gd:373` replaces itself when the manifest's
`launcher_version` differs from its own `LAUNCHER_VERSION`, and `client.gd::_maybe_update_launcher`
replaces the launcher as a bootstrap. **Both bail when the field is absent**, and the manifest was
hand-written and never carried it. So for its entire life every launcher fix has required a manual
reinstall from the website, and CLAUDE.md recorded that symptom as design: *"it does not
self-update"*. That line is now corrected, with the cause named.

**The structural half, so it cannot go missing again:** `tools/make_client_manifest.py` generates
the manifest from `VERSION.txt`, `RUNTIME_VERSION.txt` and the `LAUNCHER_VERSION` constant in
`launcher.gd` — the three places that actually own those numbers. Hand-writing a file whose fields
must match three other files is the "one value, two places" shape that caused this.
`tools/probe/launcher_selfupdate.gd` asserts the field is present, non-empty, and equal to the
constant. And `build_linux_release.sh` now runs the `--editor --quit` recompile on BOTH projects
itself, rather than CLAUDE.md asking a human to remember it before running the script.

`LAUNCHER_VERSION` 2.3 → 2.4. Verified by RUNNING the exported launcher in a clean directory and
reading the `LAUNCHER_VERSION.txt` marker it writes on startup — `2.4` — not by grepping a pck.
Release gate green on all eight checks. Seven assets up; the live manifest carries
`"launcher_version": "2.4"` and both launcher URLs answer 200. No `server/` or `shared/` change
since v0.9.771, so no redeploy.


## v0.9.771 SHIPPED (2026-09-11) -- the accuracy release, 12 commits

All 18 probes green before the build. Released as documented: changelog written, version bumped
and pushed, editor recompile forced BEFORE export, `VERSION.txt` copied into the build dir before
gating, release gate green on all eight checks including 930 dungeon-art lookups, Linux pair
built, 60-second in-game countdown sent (two players were online), binary staged as `.new` and
swapped inside the window.

Verified by the RUNNING process: `sha256 542d5e88...` on `/proc/<pid>/exe` matches the local
build. Seven assets up; both launcher URLs and the delta manifest answer 200.

**Five items were blocked on this release** -- watch the characters to L25, feel-check the rest
change, the party-broken repro, the dungeon-level second example, and the dungeon-depth
confirmation. They can now accumulate real data instead of waiting.


## LIVE REPORT 2026-09-11 (post-v0.9.770, LINUX)

- [x] **FIXED 2026-09-11 — and it was NINE sites, not "a few icons".** Owner, on Linux: *"The
      icons for the bug report and a few others aren't displaying properly (up in the very top
      right)."*
      **The distinction, measured rather than guessed.** The bundled font is Consolas and it
      covers almost nothing beyond ASCII — **not even U+266A, the music note**. Yet the music note
      RENDERS on the owner's Linux build, sitting right beside the broken icons. So symbols
      already reach a fallback font there; what that fallback does not carry is the **ASTRAL
      plane**, which is where every emoji lives. My first instinct — "use glyphs the bundled font
      covers" — was wrong, because the bundled font covers none of them either.
      **Nine sites, and the toolbar was the smallest part:** the screenshot, Suggest Idea and
      Report Issue buttons; **`⚔ Review Damage`** in combat; two scratch-off labels; and **four in
      the LAUNCHER**, which is the first thing a Linux player sees before the game even starts.
      All replaced with BMP glyphs in **U+2600–26FF, the same block as the proven-good music
      note** — U+26F6 screenshot, U+263C idea, U+26A0 report, U+2692 tools, U+2694 review damage,
      U+2630 changes.
      **THIS HAD ALREADY BEEN FIXED ONCE.** v0.9.636 stripped emoji from the bounty board and tool
      slots for exactly this reason (*"was U+1F4B0 money bag, SMP range fonts tofu it"*), and new
      ones were added afterwards. That is why the fix is a PROBE and not just an edit:
      `ui_glyph_coverage.gd` fails on any astral codepoint reaching a control's text across 11
      files, and passed 687 control-text lines. Comments and changelog prose are excluded on
      purpose — several quote the old glyph while explaining its removal, and rewriting those
      would falsify the record rather than fix a button.
      **Both launcher ZIPs were rebuilt and re-uploaded in v0.9.772** — and, as it turns out, the
      launcher CAN self-update, so Linux players get the fixed one without reinstalling. See the
      v0.9.772 entry below.

## ⚑ THE ORDER — 50 open items, sequenced so nothing gets built twice (recounted 2026-09-11)

Owner: *"How many items do we have left? Let's tackle them in an efficient order so we avoid
recreating work."* Counted after ticking 11 items that were resolved but never checked off:
**54 open across 15 arcs, 72 done** — recounted the same day at **47 open (43 + 4 partial)** after ticking seven room-pass entries that v0.9.768 had already shipped. The order below is dependency-driven, not preference —
every "before" below is a case where doing it the other way means redoing the first piece.

**0. CUT THE RELEASE. — ✅ DONE 2026-09-11, shipped as v0.9.771 then v0.9.772.** Was a gate, not
   an item. **Five open items could not progress without live data** — watch the five characters at L25+, feel-check the rest change, the "party play isn't
   working" repro, the dungeon-level mismatch second example, and the dungeon-depth confirmation.
   All five were waiting on a build in players' hands, and ~60 commits of player-facing work was
   sitting unplayed. That is now released, so they can accumulate real data. **Start the next
   session at 0b.**

**0b. BATCH THE THREE OWNER DECISIONS — DONE 2026-09-11, all four answered in one batch:**
   * **Companion return -> RECALL on the Sanctuary companions page.** Built the same day (see the
     ticked entry in Phase 3.0).
   * **Licences -> keep everything untracked, send no emails** (*"this isn't a complete enough
     project that I'm ready to send emails"*). Both unidentified packs were identified and
     credited the same day. DONE.
   * **Tier LEVEL bands -> one shared table, dungeon overlap kept as a documented per-tier
     REACH.** No difficulty change. Open item below.
   * **Card instances -> proceed now**, as step 1.

- [x] **DONE 2026-09-11 — Tier LEVEL bands: one source.** It was EIGHT copies, not three: the seven typed-out ladders (monster_database x2, combat_manager, quest_database, quest_manager, server x3) now all read `PowerRank.tier_for_level`, and the dungeon table is `PowerRank.dungeon_band()` = monster band + a named `DUNGEON_REACH` (7/7/10/10/20, zero from tier 6). Numbers unchanged: probe `tier_bands.gd` holds all 81 dungeon rank slices and all seven consumers to the old values at 37 levels; re-injecting a wrong reach fails 2. Was: three copies exist today:
      `monster_database._get_tier_info` (hard-coded thresholds), `quest_database.TIER_LEVEL_RANGES`
      (the same bands as a table) and `dungeon_database.TIER_LEVEL_RANGES` (wider below tier 6:
      1-12 / 6-22 / 16-40 / 31-60 / 51-120 against 1-5 / 6-15 / 16-30 / 31-50 / 51-100). Move
      the canonical bands into `shared/power_rank.gd` beside the ladder, make the two monster/quest
      copies read it, and express the dungeon table as base band + a named `reach` per tier so
      the numbers a dungeon uses today do not move. A probe asserts all three agree with the one
      source and that every dungeon band is identical to before.

**1. CARD INSTANCES — ✅ FIRST SLICE MERGED 2026-09-11** (per-copy UI is the second slice, see NEXT SESSION). This arc's own
   note already says it: *"this decision comes BEFORE authoring 53 dungeon cards, because the
   cards are the thing that will exist in multiples."* It is an identity change reaching the save
   format, the deck UI, the combat hand, the milestone system and the market. Authoring the cards
   first means rewriting all of that around them afterwards.

**2. SPRITE INTERIORS, Phase 3.45 — ✅ THE SLICE THAT EXISTS IS DONE (the Sanctuary, 2026-09-11).**
   The other interior on that list, NPC POSTS, turned out to BE the overworld (posts are tiles in
   the world grid, not a screen), so it moved to step 4 with the overworld. What remains here is
   nothing on its own. Historical note and the original instruction:
   *"slice it the way the dungeon was sliced, which worked: one interior end-to-end"*, and that
   instruction exists to stop 53 rooms being redone. One room end to end, look at it, then the
   remaining twelve items.

**3. 2D EFFECTS, Phase 3.46 (3 items)** — torch/lamp lighting and the atmosphere pass sit ON TOP
   of the interiors. Done first, they would be redone against the new floors.

**4. OVERWORLD SPRITES, Phase 2.95 — NOW THE BIG ONE, and strictly in order.** Phase 1 moves
   rendering to the client with NO visual change (and raises the player ceiling: it removes the
   most expensive per-player thing the server does). Phase 2 is the art, and its scope includes
   **NPC post interiors and the zoom-inside-a-post ask**, because those are overworld tiles.
   Phase 2 without Phase 1 is a rewrite. Do Phase 1 next.

**5. THE DUNGEON ARC, Phase 5 (6 items)** — atlas hub, dungeon-centred questing, the dungeon card
   pass, themed floor equipment. The 53-card content lives here and is unblocked by step 1.

**6. BALANCE, Phase 2 (2 items) — deliberately AFTER the above, not before.** CLAUDE.md: *"anything
   that changes player power invalidates it."* Card instances and the widened upgrade pool are
   player-side changes, so a per-class death-rate refit measured before them is measured against a
   player who will not exist by the time it lands. The Sage/Barbarian/Ranger gap is real but not
   broken (all three clear the endgame bar), so it can wait for one honest refit rather than two.

**7. EVERYTHING ELSE, parallel-safe (18 items).** Combat UX debt (5), party (3), input and
   accessibility (2), realm meta and sinks (3), unscheduled (5). None of these blocks or is
   blocked by the arcs above, so they are the right filler for a short session.

## STAT DESCRIPTIONS ARE A BIBLE. THEY MUST BE READ OFF THE CODE, NOT WRITTEN FROM MEMORY

Owner, 2026-09-11: *"When putting in stat descriptions that are meant to be our bible it's not
acceptable to run off intuition. Did you do the same for class stat descriptions on each of their
pages? What about the help screen? Making guesses is costing us time and leading to bad info (aka
low quality slop)."*

Correct, and the audit found more than the line that prompted it. CLAUDE.md already carries this
rule for EQUIPMENT (*"NEVER state what gear can do from memory"*); it applies to every
player-facing description and it did not get applied here.

**What I got wrong, written from intuition and shipped into the new companion screen:**
- **Speed** said *"How often it gets to act... more turns over a fight."* It does **nothing** of
  the kind. Companion speed feeds the PLAYER: initiative (`effective_dex = player_dex +
  companion_speed/2`), hit chance (`+ comp_speed_hit/3`), dodge, and flee. The companion never
  gets an extra turn from it.
- **Health** said *"Scales with YOUR max health."* That behaviour was deliberately REMOVED on
  2026-09-04, because equipping +HP gear moved the companion and levelling up shrank it. The
  companion's OWN level drives it.

**What the audit then found elsewhere, none of which I wrote:**
- **Help screen, hit chance:** stated `75% + (DEX - enemy speed)`. The code subtracts **half** the
  enemy's speed (`player_dex - int(monster_speed / 2.0)`).
- **Help screen, initiative, TWO different blocks each wrong in a different way:**
  one said `(speed-DEX)x2% chance enemy strikes first`; the other said
  `mon_spd/2 - DEX/10 (min 5%, max 45%, ambusher +15%)`. The code is a speed-scaled base, a
  logarithmic DEX penalty, clamped **5-55**, ambusher **+8**.
- **`gold_find` is a DEAD STAT.** It appears only in client display code - the Kobold's "Treasure
  Sense" passive advertises "+Valor find" and **no server or shared code consumes it**. Its
  description now says so; **wiring it is a gameplay decision and needs the owner's call.**
- A stale `x0.75` energy-scaling formula in a comment inside `stat_description_for`
  (`max_energy` normalised to x1.0 in v0.9.700).

**The class stat descriptions themselves held up.** Each already carried a verified correction in
its comment (Ranger DEX cannot crit, only the Ninja rolls Assassinate, a class only names the pool
it spends) and all eight spot-checks passed against the real formulas.

**The structural fix: `tools/probe/stat_claims.gd`.** It pins each numeric claim to the constant
or formula that produces it - crit base and per-DEX from `balance_config`, the hit-chance divisor
and clamp, the initiative clamp and ambusher bonus, all three pool formulas, the aggro cap - and
checks the class descriptions name only stats that really contribute. It deliberately tests
NUMBERS rather than prose, because every drift found here was a number. A tuning change now breaks
the CHECK instead of quietly making the help page lie.

- [x] **DONE 2026-09-11 — `gold_find` wired, and it was dead in TWO ways, not one.** Owner chose
      the faucet rather than let one be invented: *"It could offer a better chance to get the
      combat loot minigame which does give valor."*
      **Why the obvious wiring was impossible.** Its own description promised "extra gold from
      kills". `gold` is DEPRECATED (`character.gd`: *"kept for migration only"*) and an ordinary
      monster kill pays **no valor at all** — valor comes from market listings, bounties, quests,
      gambling and the Tribute card. There was nothing to scale, which is presumably why it was
      never finished. Wiring it literally would have meant inventing a new currency faucet
      scaled by kill rate, which is a balance decision and not one to make silently.
      **The two silent failures, both of which would have shipped a no-op that compiles:**
      1. `get_companion_bonus()` reads ONLY `active_companion.bonuses`, and **no companion carries
         `gold_find` there.** My first wiring read exactly that field and would have been
         permanently zero.
      2. The stat lives on the Kobold as a PASSIVE, and `_apply_companion_passive_effect` had **no
         branch for it** — the `match` fell through and dropped the effect. A match that falls
         through without a branch is the quietest way there is to lose a feature.
      Fixed at both: the applier gained a `gold_find` branch, the value rides out on the
      combat-end result, and the loot roll adds it to any `bonuses` value so **both** sources
      count. `gathering_hint` fell through the identical match and is fixed alongside.
      **Applied as a RELATIVE lift** (+20% companion takes a 7% base roll to 8.4%) rather than
      flat percentage points, which would have swamped the base and made the minigame the common
      case — the opposite of what the C3 dungeon tuning deliberately set up. Still bounded by
      `COMBAT_SCRATCH_MAX_CHANCE`, so no companion can guarantee it.
      Probe: `gold_find_wired.gd` tests REACHABILITY, not compilation — its first version checked
      only `bonuses`, failed, and is what exposed fault 1. Re-injection fails 2 checks.
- [x] **1. "Frenzied" in a monster's name is red and underlined but hovering does nothing.**
      FIXED (local). `_monster_name_label` had `meta_hover_started` connected on one line and
      `MOUSE_FILTER_IGNORE` on the next -- IGNORE means the control receives no mouse events, so
      the handler was unreachable while the `[url=]` still RENDERED as a coloured, underlined
      link. The worst shape of the bug: it advertises an explanation that cannot be reached, and
      reading the code shows a hover wired correctly one line above. Every other hoverable label
      in that panel uses PASS; this was the only IGNORE.
      Probe `hover_reachable.gd` checks the whole CLASS -- any `meta_hover_started` listener on an
      IGNORE control -- across nine client files, and asserts every rollable empowered modifier
      has hover text. Re-injection names the offending file and line.

- [x] **2. DONE 2026-09-11 — and the sweep failed THREE times before the right instrument existed.**
      Owner: *"If I right click and Inspect my companions I still see Tier 2-1... that's what I
      meant, not just some."* And: *"Stepping on a dungeon it shows Forgotten Crypt [H7] then under
      that it shows Tier 1-7 Dungeon."*

      | attempt | searched for | missed |
      |---|---|---|
      | 1st | `T%d-%d` | `T%d.%d` (all 3 stable panels) and `Tier %d-%d` (16 sites) |
      | 2nd | those two as well | bare `T%d` (8 sites incl. the Dungeon Atlas and the region line) |
      | 3rd | those as well | `quest_database`'s tier names, `T%d-8`, market rows, threat lines |

      **Each time the probe passed, because what it asserted was true and irrelevant.** That is
      CLAUDE.md's "audit written around the wrong UNIT" reached from three different angles in one
      day, and it is worth the space: I kept enumerating FORMATS when the thing to enumerate was
      SURFACES.
      **`tools/probe/tier_notation_sweep.gd` is the fix.** It does not look for spellings. It walks
      every player-facing line that FORMATS a tier-labelled specifier and demands the value go
      through a ladder helper, or that the text name a ladder which has no letters (gear / node /
      material / tool / mastery / chain). A surface written tomorrow is caught whatever format
      string its author invents. GM and debug lines are excused deliberately and the reason is
      stated in the file: an admin tool exists to read the DATA back, so the raw number that
      matches `post.tier` is the useful thing there.
      It found, and this pass fixed, roughly **40 more sites** across client, server, quest
      database, market panel and fusion panel — the Dungeon Atlas, the region line, the spawn
      picker, quest tier names, threat warnings, egg labels, fusion results, companion rows.
- [x] **3. DONE 2026-09-11 (local) — the companion INSPECT screen rebuilt.** Owner: *"is this on the to do list for
      us to update it? Is the info on it even still accurate? It doesn't even show a log of the
      companions stats. It should show their stats and each should be hoverable so players can see
      what they do. For example, What does Aggro do? What does spd do for a companion, etc. It
      also doesn't list the card they provide in combat or anything."*
      **On accuracy: NO, and measurably so.** `_get_variant_multiplier` in client.gd is a
      hardcoded twelve-NAME list -- the stale per-name table deleted on 2026-09-03 and replaced by
      a rarity-derived function. It is the FOURTH surviving consumer of that dead table. Measured:
      **111 of 119 variants (93%) show the wrong stat multiplier** -- Golden reads 1.00x and is
      really 1.05x; Infernal reads 1.00x and is really 1.22x.
      `_get_sub_tier_multiplier` has the right values but is a hand-copy of
      `COMPANION_SUB_TIER_MULTIPLIERS` -- the same "one value, two places" shape, not yet wrong.
      **What the screen must gain:** the companion's own STATS (combat HP via
      `Character.calculate_companion_max_hp`, damage range, aggro role, speed), each HOVERABLE
      with what it actually does; the **combat card it grants** (`companion_card_id_for` ->
      `COMPANION_CARD_DATA`, giving name / kind / desc), which is absent entirely; and a
      multiplier breakdown read from the shared sources rather than copies.

- [x] **3b. DONE 2026-09-11 (local) — companions screen + one Power number.**
      Owner, 2026-09-11: *"when we work the companions Inspect we also need to comb over the
      Companions Screen as well. The multiplier is confusing to the players in its current form so
      we need to simplify it or make it easier for them to understand what it is they are looking
      at."*
      **Why it is confusing, concretely.** A companion's power comes from THREE multipliers shown
      in three different formats, which then MULTIPLY together and are never totalled:
      `(+60% stats)` for the variant, `(x1.4 stats)` for the rank, `(+25% stats)` for the border.
      A player reading "+60%", "x1.4" and "+25%" cannot combine them, and none of the three is the
      number they actually want.
      **The fix is to show the EFFECT, not the arithmetic** -- the same rule applied to the tier
      ladder and to card upgrades earlier today. Lead with real stats (combat HP, damage per turn)
      because that is what the multipliers exist to produce; give ONE combined figure if a
      multiplier is shown at all; put the three-way breakdown in the hover for anyone who wants
      it. Nobody should have to multiply three differently-formatted numbers to learn whether
      their companion is good.
      **And it must read from the shared sources** -- see item 3: the variant multiplier is
      currently wrong for 93% of variants precisely because this screen keeps its own copy.

- [x] **4. DONE 2026-09-11 (local) — the bar is on every companion surface.** Owner: *"all I see to
      signify Tier and rank is H1 and G1. What happened to the bars or ways to make it obvious
      which tiers and ranks are better?"*
      The panels call `PowerRank.tag()`, which is colour-only. `rich_label()` (colour + the
      explaining hover) and `pips()` (the filled bar) both exist and are unused there -- colour
      alone is exactly what the owner said was not enough when the ladder was designed.

      **What landed across 3 / 3b / 4, all in one pass:**
      * **Accuracy.** `_get_variant_multiplier` was a hardcoded twelve-NAME list — the fourth
        surviving consumer of the per-name table deleted on 2026-09-03. **111 of 119 variants
        (93%) showed the wrong multiplier**; now zero, asserted over the whole variant table.
        `_get_sub_tier_multiplier` reads `COMPANION_SUB_TIER_MULTIPLIERS` instead of repeating it.
      * **ONE Power number.** variant x rank x border are combined into a single `Power x2.14`,
        with the three-way breakdown in the hover. The two duplicate `(+N% stats)` suffixes are
        off the name line, and the dead code behind them is gone.
      * **Stats, each hoverable.** Health (through the SHARED
        `Character.calculate_companion_max_hp`, not one of the client's old mirrors), Damage,
        Aggro and Speed, every row built by `_companion_stat()` against one
        `COMPANION_STAT_HELP` table so no stat can end up unexplained.
      * **The combat card it grants** — absent entirely before — with its name, what it does, and
        progress toward making it permanent, which is the thing a player is working for.
      * **The ladder bar** (`PowerRank.pips`) on the inspect screen, the active companion line,
        the kennel cards, the grid rows, the kennel panel and the fusion panel; the active line
        and inspect header also carry `rich_label`, so the ladder explains itself on hover.
      **A rendering bug found while verifying, which affected EVERY `rich_label` in the game:**
      `PowerRank.hover()` marked the current tier as `[E]`, and `[url=VALUE]` ends at the first
      `]` — so the whole ladder spilled into the visible line as plain text. The inspect header
      read *"...any G beats every H.]G5  Level 12"*. Markers are now `>E<` and every hover goes
      through a `_url_safe()` strip rather than relying on each string being written carefully.
      Probe: `companion_inspect.gd`. Re-injection of three faults — the stale name table, the card
      section removed, the bracket in the hover — fails 6 checks.
- [x] **5. SOLVED 2026-09-11 (local) — 58 GHOST TRADING POSTS were projecting invisible safe
      zones.** Owner: *"I'm at coords -44, -34 and it is saying It's a Safe Zone in the top right
      of my screen but there is no post. I'm just standing on a road surrounded by a bunch of
      water."*
      They were right, and it was not their tile. `trading_post_database.gd` still defines **58
      LEGACY fixed posts** from the old world model. They are never stamped into any chunk —
      verified against live server data, where the chunk covering that tile holds 45 modified
      tiles and every one is a `path`. But `world_system._tile_to_terrain` still asked that table
      "is there a post here", got YES for a post named **Southwest Grove**, and returned
      `Terrain.TRADING_POST`, which is `safe: true`, which makes `get_monster_level_range` return
      base_level **0**, which the HUD prints as "Safe Zone".
      **Measured: 194 tiles claimed within ±120 of origin alone** (214 within ±140). Each is an
      invisible safe pocket — and the consequence is worse than a wrong label, because
      `check_encounter` returns false in a safe zone, so **no monster could spawn on any of
      them**. All 58 survived the world reset, being a hardcoded table rather than world data.
      **Fixed at the ONE place the geometry is built** (`_build_tile_cache`, behind
      `LEGACY_POSTS_CLAIM_TILES = false`) rather than at the twelve call sites — a fix applied to
      some of twelve is exactly the shape that produced the incomplete tier sweep the same day.
      The table itself is kept: `resolve_post_category` and the NPC stock helpers are keyed by
      post id/dict, not by tile, and still serve LIVE posts through that same code.
      Probe: `ghost_safe_zones.gd`, which sweeps ±140 rather than checking the one reported tile —
      the report was a sample of a pattern. Re-injection fails 4 checks.
      **Four wrong theories before the measurement, worth recording:** an unstamped NPC post (no —
      no post record covers the tile), a settler bubble (no — `player_tiles.json` is empty, so no
      bubbles exist), the distance curve returning 0 (no — it floors at 1), and the pull-down
      blend (no — running the real function against the live post file returned level **11**).
      Only stubbing the legacy table into the repro found it, because that was the one input I
      had not reproduced.
- [x] **6. ANSWERED by the owner and by the fix. "Safe zones should be within posts normally."**
      The ghost-post removal (item 5) achieves exactly that: those 194 tiles now report their real
      danger level, and safety comes only from genuinely stamped post tiles. No reword needed —
      the flag was not lying about the rule, it was being fed a lie by 58 posts that do not exist.
- [x] **Shutdown handler fired every frame until the process exited — FIXED 2026-09-09.**
      `_execute_pending_shutdown` awaits a second (so the goodbye broadcast lands before sockets
      close), and `_process` keeps running across an await with `pending_update_active` still true
      and the counter at zero — so it re-entered every frame. 60fps x 1s = the 61 copies seen in
      the v0.9.763 deploy log, meaning any connected player was told the server was shutting down
      sixty times. Latched inside the function rather than at the call site, since the re-entrancy
      is a property of the function being async. Verified on production by springing a real
      countdown: **1** shutdown line and **1** broadcast, down from 61.

- [x] **CONFIRMED ON SCREEN 2026-09-10.** The owner hovered a theme tile in the KEY and the
      same tile on the FLOOR, and the tooltip wrapped rather than running off the edge: *"3a
      Working. 3b Working. 3c Seems to wrap, it's on two lines."* This was the only part a
      screenshot could not settle, because it needs a real mouse.

- [ ] **Watch the five live characters at L3-L12.** They sit in exactly the range everything shipped
      on 2026-09-07 targets, and they are now better evidence than more simulation.
      `bash tools/check_player_progress.sh` — at L25+ re-validate `make_char` against real saves;
      at L50+ the high-level balance work can finally be checked against real data.
- [x] **Deck repair CONFIRMED WORKING on live data — 2026-09-08.** It runs on character load, so
      it has fired on the two characters that have logged in since it shipped and not on the rest:
      * `Dexto` (Ranger L6, repair=1): exactly the 5-card Ranger starter.
      * `p3snarujuppo` (Ninja L9, repair=1): the 5-card Ninja starter + `companion_card_kelpie`,
        which the repair keeps ON PURPOSE (a drop the deck screen cannot re-add). It also holds
        `distract`, which is NOT a Ninja starter card — but `distract` is in the roster and
        re-addable from the deck screen, so that is a manual add after the repair, which is the
        documented intent ("players can customize manually again"). Not a defect; recorded because
        a 7-card deck looks like one at a glance.
      * The seven that have not logged in still read `deck_repair_version = -` with 7-13 card
        decks (`Caps2` 12, `CapsUndeadBarb` 13). They will repair on next login. Correct by design.
- [ ] **Feel check the rest change.** `REST_HEAL_MIN/MAX` replaced EIGHT sites, so meditate and
      companion regen scaled along with rest and mages got it twice. Owner: Meditate is the
      deliberate lever if mages come back too strong — check that BEFORE touching mage design.

## Phase 2 — balance follow-through (cheap audits, no chain)

- [ ] **Sage 1.3%, Barbarian 1.2%, Ranger 1.9%** death per encounter against 0.1-0.7% for the rest.
      Real but not broken, and all three clear the endgame bar. Per-class levers only.
- [ ] **The win targets at high level predate retreat.** 60% was chosen when a "loss" meant a death;
      it now mostly means a retreat. Revisit alongside the Unburied, since extra lives change what
      survival means. `refcal` REPORTS death rate now but cannot steer by it — at a ~0.3% target
      there is under one expected death per sample, so there is no signal to correct against.
- [x] **Magic Bolt damage vs investment — RESOLVED 2026-09-07** (`magecost` audit, n=40 through the
      real cast path). It is exactly the design asked for: **highest single-cast damage at every
      level** (452 / 1,743 / 6,368 at L10 / L50 / L200) and the **least mana-efficient card from L50
      onward** (11.8 dmg-per-mana against Meteor's 18.3 at L200). You burst with it and sustain with
      Blast or discharge with Meteor. Meteor's lead is understated: measured at ZERO Focus, and the
      discharge is its whole point.
      Residual, minor: at **L10** Bolt is both the biggest hit and marginally the most efficient
      (25.8 against Blast's 23.0). A 12% edge is a preference, not a trap — revisit only if early
      mages read as one-button.
- [x] **Overload RETIRED 2026-09-07** — owner approved removing it rather than re-pricing again.
      It was the only card that cost HEALTH in a game where health is the resource you die from,
      spent against a 30% retreat threshold, so no price worked: at 20% of max HP it cost the
      Sorcerer 81/53/65 -> 96/65/71, and re-priced to 12% it STILL gave 2/40 survivors against
      12/40 for the card it replaced. **Damage does not save you; hit points do.**
      Off the roster, migrated out of existing decks on load (same as `all_or_nothing`), and the
      cast path kept as a branch that TELLS a player who still has it bound rather than failing
      silently — the treatment Outsmart got. `-- verify` now asserts it REFUSES, since a retired
      card that still casts is the bug worth catching.
- [x] **Vestigial ability `level` fields — the PLAYER-FACING half fixed 2026-09-07.** Confirmed
      nothing gates on them: no resolver, sort or filter reads an ability's `level`. But they had
      leaked into the help page, which listed "L100 Devastate" and "L25 Shield Bash" a few lines
      above "all available from level 1" — a direct contradiction on the same screen, telling a new
      player they could not have their finisher until level 100. All 24 prefixes removed and the
      clarifier moved to the top of each list.
      The dict fields themselves are left in place: they are inert, and removing them touches every
      ability entry for no player-visible gain. If they are ever removed, do it in one pass and
      re-run `-- verify`.

## ⚑ CARD INSTANCES + a WIDE upgrade pool (owner direction 2026-09-10) — the chase loop

Owner, after playtesting cycle values: *"Card upgrades should always be something worth chasing
and make Milestones exciting. The pool of them should be wide enough that some players are telling
their friends about ones they found that their friends have probably never seen."*

**The loop this is meant to create:**
1. Earn a card from a dungeon (companion or dungeon-specific).
2. Put it in the deck and LEVEL IT UP, hoping for good milestones to stack on it.
3. If the rolls disappoint, **sell it on the market** and try again with a fresh one.

**The architectural consequence, which is the expensive part — do not start the content pass
without deciding this first.** Duplicate cards must become **unique INSTANCES**: usage and
milestone picks tracked *per copy*, so two Venom Fangs can carry different upgrades and a player
can chase a better roll. Today all progression is keyed by CARD ID:
  * `combat_deck_collection` is `{card_id: count}` — a count, with no identity per copy
  * `ability_uses[card_id]` — shared across every copy
  * `ability_milestone_picks[card_id]` — shared across every copy
  * the market lists a card by id (`handle_market_list_card`), so "sell THIS one" has nothing to
    name yet
  * the deck screen and the combat hand address cards by id throughout
So this is not a table change; it is an identity change that reaches the save format, the deck UI,
the combat hand, the milestone system and the market. It also needs a migration for existing
saves, and `MAX_ABILITY_COPIES` (3) starts meaning something different.

**Sequencing:** this decision comes BEFORE authoring 53 dungeon cards, because the cards are the
thing that will exist in multiples. Widening the upgrade pool can start earlier and independently —
today there are three reveal upgrades and five cycle types, which the owner's own playtest answer
("depends what upgrades hit your cards") already suggests is too thin to build a chase on.

- [x] **DONE 2026-09-11 — the upgrade pool can make things rare now.** Owner's goal for the arc:
      *"wide enough that some players are telling their friends about ones they found that their
      friends have probably never seen."*
      **The cause was the DRAW, not the size.** `draw_choices` did `pool.shuffle()` and took the
      first 9 — uniform, so nothing could be rare at any pool size, and adding entries would have
      dissolved into the same draw. Replaced with a weighted draw without replacement
      (`WEIGHT_COMMON 10` / `WEIGHT_RARE 1`), 14 of 51 upgrades marked rare.
      **Measured on the real draw over 4 000 runs, not simulated:**

      | kind | rare seen after m1 | m3 | m5 | common at m5 |
      |---|---|---|---|---|
      | damage | 6% | 11% | **20%** | 87% |
      | buff | 10% | 20% | **31%** | 94% |
      | control | 9% | 18% | **34%** | 96% |

      Against ~95% of everything seen after five milestones before. Commons stay freely
      available, which matters — the pool must still feel generous.
      **RARE MEANS DISTINCTIVE, NOT STRONGER — a deliberate call.** Tying rarity to power would
      make luck decide how strong a card ends up, which is a balance problem wearing a content
      hat. The rare set is the upgrades that BREAK A RULE the player has learned: pay off from
      the discard (the three REVEALs), act before the fight starts (Preload), reach an ally
      (Shared), take another turn (Swift), cost health instead of resource (Blood Price), invert
      the resource relationship (All In), pull the enemy off your companion (Provoking), land on
      YOU (Unstable Hex), or sometimes do nothing at all (Gambler's Cut).
      The legacy four stay common on purpose — `draw_choices` falls back to power/efficiency when
      the pool runs dry, so a rare fallback would make the safety net itself unreliable.
      **And the player is TOLD.** A rare pick shows a ✦ marker, gold text and *"rarely offered"*
      on the card, plus *"most players will not have seen this one"* in the hover. A rare
      trade-off keeps the ORANGE trade-off colour — orange is a warning and gold is decoration,
      and decoration must not overwrite a warning.
      **The near-miss worth recording:** `_build_upgrade_offer` rebuilds each upgrade as a
      FOUR-FIELD SUBSET before it goes on the wire, so `rare` never reached the client. The UI
      work was complete and would have rendered every pick as common — a no-op that looked
      finished. Caught by asking what the wire actually carries instead of assuming the dict
      travels whole; the probe now asserts that line specifically.
      Probe: `tools/probe/upgrade_rarity.gd`. Re-injection (uniform draw + `rare` stripped from
      the wire) fails 4 checks.
      **EXTENDED to FOUR TIERS the same day, on the owner's direction.** *"If we are going to
      have rarity with cards we may want to add more than just rare, maybe uncommon as well. They
      should also be visually distinct, colored by [rarity] or have a visual gauge so they can be
      differentiated from commons at a glance during the upgrade offer."*
      `common / uncommon / rare / epic` — **the loot vocabulary, not a new one**. Same names, same
      `DropTables.RARITY_COLORS` hues, so a purple upgrade reads like a purple item with nothing
      new to learn. Distribution 25 / 12 / 10 / 4, weights 10 / 2.5 / 0.8 / 0.30. Measured over
      4 000 runs on the real draw:

      | kind | | common | uncommon | rare | epic |
      |---|---|---|---|---|---|
      | damage | m1 → m5 | 69 → 97% | 25 → 62% | 9 → 26% | 3 → 10% |
      | buff | m1 → m5 | 76 → 98% | 29 → 71% | 10 → 32% | 4 → 16% |
      | control | m1 → m5 | 78 → 100% | 32 → 88% | 11 → 45% | 5 → 18% |

      **THE MEASUREMENT FOUND A REAL DEFECT, not just a tuning number: CONTROL could never be
      offered an epic — 0% at every milestone.** All four epics were DAMAGE- or BUFF-kind, so a
      control card was structurally locked out of the top tier. No weight would have revealed
      that; only counting the eligible pool per kind does. `opening_act` (ANY) and `provoking`
      (CONTROL) were promoted, and the probe now asserts every kind can be offered every tier.
      **Visual:** the tile BORDER takes the rarity colour — dimmed by rarity so common, which is
      white, does not end up the brightest thing on screen — the NAME takes the colour, and a
      four-cell **gauge** (`◆◇◇◇` … `◆◆◆◆`) carries the same information as a SHAPE, because
      green and blue are the pair most often confused and they are exactly uncommon and rare.
      Rare+ also gets a heavier frame. The gauge is sized off `RARITY_ORDER`, so a fifth tier
      cannot leave it behind.
      **The trade-off warning keeps the BACKGROUND.** Orange is a warning, rarity is decoration,
      and decoration must not overwrite a warning — so an epic trade-off still reads as a
      trade-off first.
      Re-injection: flattening the weights and stripping `rarity` from the wire fails 2 checks.

- [x] **DONE 2026-09-11 (steps 1-3). The pool was same-y and the upgrades were INVISIBLE after you picked
      them.** Owner: *"How different are each of the cards though truly? Many of them feel like a
      bit of the same and many of them are fairly situational. Situational can be good but only
      if there is a clear answer to how to use them properly and make it easily apparent in
      combat when it's worth using. If not it all becomes micro-management and feels like dead
      options."* Audited rather than argued — `tools/probe/upgrade_variety.gd`.

      **(a) The sameness is real.** What number each upgrade moves:

      | channel | n | | channel | n |
      |---|---|---|---|---|
      | damage | **13** | | heal | 4 |
      | resource | 8 | | crit / turn / mitigate / chip | **1 each** |
      | shield | 6 | | | |
      | buff strength | 6 | | | |
      | engine | 5 | | | |
      | control | 5 | | | |

      Thirteen ways to say "the damage number goes up", and the genuinely distinct effects — an
      extra turn, damage mitigation, a crit chance, chip damage from the discard — are ONE ENTRY
      EACH. The variety is in the long tail and the tail is one card wide.

      **(b) "Situational" is LESS true than it feels, which makes (a) worse.** 27 always-on,
      9 pure variance (a 12% crit chance is not a decision), and only **15 genuinely
      conditional**. So most of the pool is 27 always-on upgrades that largely move the same
      number — interchangeable, which is exactly the "bit of the same" feeling.

      **(c) The triggers are mostly NOT hidden — 9 of 15 are already on screen.** Foe HP,
      your HP, the resource bar and the monster's status chips already show Executioner,
      Closing Cost, Vindication, Desperation, Bulwark, Kindling, All In, Harrying and
      Demoralising. Genuinely blind: **Opener, Opening Act** (first use this fight),
      **Relentless** (every 3rd cast) and the three **REVEALs** (fire when you do NOT play it).

      **(d) THE ACTUAL GAP, and it applies to all 15 equally.** Nothing connects the visible
      state to the card:
      * the upgrade table carries **no machine-readable trigger** — the condition exists only in
        English prose, so nothing downstream *can* know when an upgrade is live;
      * a card in the combat hand does not show **which upgrades it carries at all** (verified:
        `combat_scene_panel.gd` mentions milestone picks only in the CHOOSER, never on a played
        card);
      * so nothing can say one is **live this turn**.
      A player picks Executioner at a milestone and it vanishes into the card's invisible state.
      The foe drops to 25% — the most visible number on the screen — and the player still has to
      *remember* which of five cards carries it. That is the micro-management the owner means,
      and it is not caused by the triggers being obscure.

      **STEPS 1 AND 2 DONE 2026-09-11** (owner: *"Order looks good, proceed."*).
      **1. The condition is DATA.** 24 of 51 upgrades carry a structured `trigger`
      (`foe_hp_below` / `self_hp_below` / `first_use` / `resource_full` / `resource_low` /
      `foe_stunned` / `on_kill` / `cast_cadence` / `on_cycle` / `chance`), with thresholds read
      from what the server actually rolls against — 30% for Executioner, 50% Bulwark, 34%
      Desperation, all asserted against `combat_manager`. `trigger_live(u, state)` answers "is
      this live right now" and `trigger_hint(u)` gives the plain-language note. Both live in
      `card_upgrades.gd`, not the client, because the server rolls the real effect against the
      same facts and a client-side copy of "below 30%" is the shape that drifts.
      **Two rules the evaluator enforces:** a MISSING fact reads as not-live, so a caller that
      knows less under-lights rather than claiming something untrue about a turn the player is
      about to spend; and always-on and pure-chance upgrades NEVER light — if everything glows,
      nothing does.
      **2. The hand shows it.** A card renders the upgrades it carries, live ones named and lit,
      the rest as dots, nothing at all when it has none:
      ```
        foe at 80%, 1 cast in      ○○○
        foe at 22%, 1 cast in      ● Executioner  ○○
        foe at 22%, 2 casts in     ● Executioner · Relentless  ○
      ```
      The rank-up card also tags the condition (`▸ foe under 30%`, `▸ every 3 casts`) so nine
      offers can be SCANNED for which ones only pay in a moment — prose cannot be scanned.
      **A counter had to exist for it.** First-use and every-Nth-cast could never light without
      per-card cast counts, and the two trackers that existed (`opener_used_<id>`, a bool, and
      `_relentless_<id>`, a counter) are each maintained only when the player happens to OWN that
      upgrade — a third of that shape would have been the mistake CLAUDE.md warns about. One
      generic uncapped `casts_this_fight` now counts at the single successful-cast site and is
      sent by BOTH combat-state builders. The two existing effect paths are deliberately left
      alone: folding them in is an off-by-one risk on live behaviour for no visible gain, and is
      worth doing on its own.
      Probe: `tools/probe/upgrade_triggers.gd`. Re-injection of four faults — a threshold that
      disagrees with the server, an unknown fact claiming live, one state builder dropping the
      counts, the hand not consulting the shared evaluator — fails 5 checks.

- [x] **3. DONE 2026-09-11 — authored AGAINST the measurement, five upgrades, all wired.**
      Pool 51 → 56. Nothing added moves the damage number, because damage already held 13 of the
      13 / 9 / 6 / 6 / 6 / 5 / 5 / 2 / 2 / 1 / 1 channel spread, and three of the five are
      `KIND_ANY` because that is the only way to lift BUFF and CONTROL at once.

      | upgrade | kind | rarity | trigger | channel it widens |
      |---|---|---|---|---|
      | **Sure Strike** | damage | rare | first use | crit (1 → 2) |
      | **Last Stand** | any | **epic** | you under 25% | mitigation (1 → 2) |
      | **Second Look** | any | **epic** | if NOT played | REVEAL (3 → 5) |
      | **Slow Mend** | any | uncommon | if NOT played | REVEAL |
      | **Rally Point** | any | uncommon | foe under 50% | engine |

      **The thin cells moved**, which was the whole point:
      buff-uncommon **4 → 6**, epic-for-buff **2 → 4**, epic-for-control **2 → 4**,
      damage-uncommon 10 → 12, damage-epic 4 → 6.

      **Two of the five cost almost nothing to wire, because the lever already existed.** The
      cycle system supported FIVE effect types (engine / shield / heal / resource / chip) and the
      three REVEALs used only three of them — `heal` and `resource` were sitting unused. New
      content in the pool's most distinctive channel for the price of a table row.

      **What I did NOT add, and why.** The extra-turn channel still has one entry. Expanding it
      was rejected on reading the code rather than on taste: `combat_manager` already notes that
      two stacking extra-turn rolls is how an infinite chain becomes possible, and Swift rides the
      existing roll for exactly that reason. Adding a second source is a real risk for a channel
      that is thin on purpose.
      Several other thin cells could only have been filled with NEAR-DUPLICATES — a buff-card
      shield below half health is Bulwark, a shield while the foe is stunned is Demoralising, a
      free first cast is Opening Act. **Those cells need new LEVERS in the combat code, not new
      table rows**, and adding the duplicates would have made the exact "bit of the same" problem
      worse while appearing to fix it. That is the honest remaining work.

      **Each one is proven to FIRE, not merely to exist** — `tools/probe/upgrade_new_wired.gd`
      drives real casts and looks for the effect, because an upgrade that sits in the table and
      never fires is the dead option this whole arc removes, and it is the failure that looks
      finished: card renders, rarity shows, trigger tag reads correctly, effect absent.
      Re-injection (Sure Strike unwired, Last Stand unwired, one of the two reveal chains
      half-updated) fails 6 checks.
      **One shared-state bug caught while wiring:** the crit announcement was hard-coded to
      "Keen Edge", so Sure Strike would have announced an upgrade the card does not carry. The
      line now names its real source via `combat["_crit_label"]`.
- [x] **DONE 2026-09-11 — five upgrades authored against the channel table.** *"I don't think
      our upgrade pool currently offers enough distinctive and interesting options as of yet but
      this is a start at least."* Agreed, and the rarity work makes the gap measurable rather
      than a feeling. Eligible counts per kind now:

      | kind | common | uncommon | rare | epic |
      |---|---|---|---|---|---|
      | damage | 14 | 10 | 5 | 4 |
      | buff | 14 | **4** | 6 | **2** |
      | control | **9** | 6 | 5 | **2** |

      The thin cells are where a player runs out of new things to see: **buff-uncommon (4)**, and
      **epic for buff and control (2 each)**. Control's COMMON pool is also the smallest at 9,
      which is why its coverage saturates — nine-of-twenty-two shown five times will cover most
      of a thin pool, and that is arithmetic no weight beats.
      **Author upward, not outward:** more commons do not help: they are already at 97-100%
      coverage by milestone 5. The value is in uncommon and above.
      **The bar for a new entry, from what the rare set already does:** it should BREAK A RULE the
      player has learned — pay off from the discard, act before the fight starts, reach an ally,
      take another turn, cost health instead of resource, invert the resource relationship, pull
      the enemy off your companion, land on YOU, or sometimes do nothing at all. A percentage on
      an existing number is a common, however large the percentage.
- [x] **DONE 2026-09-10 — Props are no longer erased by anything standing on them.** Owner:
      *"when a sprite steps on a space with a decorative piece on it the decorative piece seems to
      go away"*, then after living with it: *"The occlusion just makes it look janky currently.
      We need to find a solution or a way to make it work well."*
      **What unlocked it.** The entry below used to say "no cheap fix yet", because the two known
      routes were both expensive: offline pre-baking multiplies (props x every player frame x
      companion x 53 monsters), and runtime compositing looked like it needed the grid rewritten
      from one BBCode string into an `add_image()` token stream. The second assumption was wrong.
      `Resource.take_over_path()` puts a texture into the engine's resource CACHE under a chosen
      path, and `ResourceLoader.load()` — which is exactly what RichTextLabel's `[img]` tag calls —
      checks that cache before it touches the disk. So an image composited in memory can be handed
      to the renderer as an ordinary `res://` string and NOTHING about the grid emitter changes.
      Probed before any of it was written (`tools/probe/dyn_texture_bbcode.gd`).
      **How the sprite's background is recovered.** There is no alpha left — the bake already
      flattened it — so it comes back by COLOUR KEY on the flat `#524B24` floor, restricted to
      pixels reachable by flood fill FROM THE TILE EDGE. Border-connected matters: a troll has 24
      floor-coloured pixels *inside* it and a plain colour key would punch prop speckles through
      its middle. Both halves are asserted in `tools/probe/prop_occlusion.gd`, and the interior
      assertion was proven to fire by disabling the flood fill and watching it go red — the first
      two versions of that assertion passed with the fault injected and were measuring nothing.
      Cost: 0.27ms per cold (sprite, prop) pair, cached for the session; 2000 warm lookups in
      1.1ms. Applies uniformly to the player, the companion, every monster, floor loot and eggs.
      **This is also the layer TALL PROPS need** — see below.

- [x] **DONE 2026-09-10 - licence-restricted art purged from git history.** 1,576 files
      untracked, then removed from all 1,688 commits with `git filter-repo` and force-pushed.
      Verified after: 0 blobs of any restricted path remain reachable; commits 1688/1688 and
      tags 792/792 preserved; the working tree is file-for-file identical to before; the art
      gate and occlusion probe still pass from disk. Every GitHub Release survived with all 7
      assets, and the launcher's own endpoint plus its `releases/latest/download` URL both
      answered (HTTP 200, 38MB) - that was the one step that could have reached players.
      Backups taken FIRST, at `Documents/phantom-badlands-backup/<timestamp>/`: a 147MB full pre-rewrite
      mirror and a 28MB copy of the art itself.
      New guard: `tools/check_licensed_assets.sh` + `tools/licensed_assets.manifest`, wired into
      the release gate, so a build cannot ship without the art present. Proven by hiding
      `prop_floor32` and watching it go red.

- [ ] **AWAITING GITHUB: garbage collection of unreachable objects.** Request SUBMITTED
      2026-09-10 via the Support virtual assistant ("Yes, but I need help removing of cached
      commits"). Helpful facts established while filing, all verified rather than asserted: the
      repo has **0 forks** and **0 pull requests ever** (no `refs/pull/*`), so the objects exist
      only here and no fork owner has to be chased - that is the usual reason these requests
      stall.
      Framing matters if they come back: this is a LICENCE-COMPLIANCE obligation, not a leaked
      credential. GitHub's stated bar is "sensitive data that cannot be mitigated by rotating
      affected credentials", and the honest argument is that rotation is INAPPLICABLE here - the
      risk is that the files remain downloadable, not that a secret is usable. They may still
      decline as out of scope; that is a reasonable outcome and the answer is then to leave it.
      We cannot escalate - the DMCA route belongs to the copyright holder, not to us as licensee.
      **Re-check with `bash tools/check_github_gc.sh`** rather than guessing. As of submission it
      still reports all three sample SHAs at HTTP 200 and the repo at its pre-rewrite 120,127 KB.
      When it goes green, update `docs/ASSET_LICENCES.md` and tick this.

- [x] **DONE 2026-09-10 - private art backup exists.**
      <https://github.com/Dextobust33/Phantom-Badlands-Art> (private, 1,849 files) holds every
      path in `tools/licensed_assets.manifest` plus the 20 untouched purchased Raven `.zip`
      files. Verified by MD5 against the working tree - 0 missing, 0 differing - and by an
      actual RESTORE DRILL: `prop_floor32` deleted, gate went red and named it, restored from
      the repo by the documented command, gate went green, occlusion probe passed. A backup that
      has never been restored from is a hope, not a backup.
      Risks accepted knowingly and written down in `docs/ASSET_LICENCES.md`: a private repo is
      one click from public, and it stores plaintext on a third party.

- [~] **PARTLY DONE 2026-09-11.** Written and committed: `bake_landmark_tiles.py`
      (tile_floor32, with a fragment test that refuses half an object), `bake_glyph_tiles.py`
      (the glyph tiles, with a font-coverage assertion that refuses to bake a missing-glyph box)
      and `bake_egg_variants.py` (the variant->egg table, as a collision-free assignment).
      STILL MISSING: `prop_floor32` (11), `free_floor32` (5) and `egg_floor32` (100). Those three
      remain irreplaceable data.

- [x] ~~Write the BAKE GENERATORS as committed tools. The real fix behind the backup above.
      `prop_floor32` (11), `tile_floor32` (18), `free_floor32` (5) and `egg_floor32` (100) are
      134 baked PNGs whose generator scripts **do not exist** - checked, no commit ever added
      one. They were ad-hoc and are gone, so those files are currently irreplaceable data rather
      than reproducible output.
      The generators are OUR code operating on assets we own, not licensed art, so they belong
      in the PUBLIC repo. Writing them turns 134 irreplaceable files into build output, lets a
      fresh clone rebuild everything from the source packs alone, and shrinks what the private
      repo has to guard to just the purchased packs. Roughly an hour; retires the class.
      Everything needed to write them is in `client/dungeon_tiles.gd` (sheet paths, cell
      coordinates, `FLOOR_COLOR`) and `client/dungeon_sprites.gd` (the glyph and tile tables).

- [x] **DONE 2026-09-11 — decided AND both packs identified.** Owner: keep untracked, no emails
      yet. `darkcave/` is PixelHouse's *Retro fantasy RPG dark cave tiles* (found through its own
      licence wording); `tilemap_pack/` is Henry Software's *Pixel Level (free)*, **CC0**, proven
      by MD5 against the RageTileMap repo beside it. Both credited; `docs/ASSET_LICENCES.md`
      updated. Asset licences: two open items (raised 2026-09-10 by the owner asking whether the Raven
      packs are legal to have in the repo — see `docs/ASSET_LICENCES.md` for the full record).
      Raven Fantasy is settled: commercial use unlimited, attribution welcome not required, but
      *"cannot be distributed or sold as a separate product"* — so `client/sprites/raven/` is
      gitignored and ships inside the `.pck` instead. Still open:
      (a) `pet-egg-pack` (1,298 raw PNGs tracked) carries a Hope2D clause against redistribution
      "in a standalone or reusable asset form" — the same shape, already live. Decide: gitignore,
      ask permission, or accept the reading.
      (b) `darkcave/` and `tilemap_pack/` — the sheets the entire dungeon tile pass is built on —
      have no licence file and no `CREDITS.md` entry. Track down and record.
      Cheapest fix for (a) and for Raven both: one email asking for written permission.

- [x] **DONE 2026-09-10 - two-cell props span two cells.** The lamps and the dead shrub are back,
      drawn as top and bottom HALVES into two grid cells instead of one cell holding half an
      object. Owner's original report: *"the two lanterns you added in those are actually two
      vertical squares tall... currently they render as half of a lamppost."*
      The placement rule is the fix, not the art: a base is only allowed where the cell ABOVE is
      also walkable, so a top half can never land in a wall or the void - which would be the same
      half-object bug moved up one cell. 1 in 55 eligible cells against 1 in 7 for scatter,
      because a lamppost is a landmark and a floor covered in them is a street.
      The halves stay TRANSPARENT and go through `overlay`, so they are part of the GROUND: a
      monster standing at a lamp composites over it rather than erasing it, which is the
      occlusion layer paying for itself a third time.
      Needed one new asset with no obvious home: the CORRIDOR floor as a standalone file. It is a
      sheet region everywhere else, which is fine for drawing and useless to a compositor. Baked
      as `room_floor32/corridor_00.png`, deliberately outside `ROOM_PACKS` so no room can pick it.
      `tools/probe/tall_props.gd` checks both halves exist, that no base on six generated floors
      puts its top into a wall, the density, and that placement is stable rather than shimmering.
      **This is also the row split MULTI-TILE DECOR needs** - the mechanism is now there, and what
      is left for decor is choosing 2-cell objects from the packs.

- [x] **SHIPPED v0.9.767 (2026-09-10).** Cycle values + the three reveal upgrades, arrow-key
      diagonals for keyboards with no numpad, prop occlusion (entities draw OVER scatter) and
      scatter under theme-tile glyphs, hoverable damage on companion/dungeon cards, the
      absorbed-hit line, the egg hatch that blanked the dungeon floor, the final chest reward
      that was being built/sent/discarded, and party leadership transfer on all three exit
      paths plus permadeath. Plus two repaired gates: the dungeon-art scan (red on master for a
      literal-newline split bug) and a new licensed-assets check. Admin panel reorganised.
      Playtested A-F by the owner before shipping; server deployed and verified by hashing the
      RUNNING process; all 7 assets live; published pck re-downloaded and confirmed 0.9.767.
      STILL UNVERIFIED and shipped on code review: party equipment rewards (2 clients) and
      leader logout/permadeath (3 clients) - `party3` and `party3_leader_dies` set both up.

## Phase 2.7 — EQUIPMENT COMPARISON HIDES THREE ATTRIBUTES (owner 2026-09-11)

Owner: *"equipment comparisons may be missing some stats like Dex"*. Correct, and it is wider
than DEX. Checked `_get_item_comparison_parts` (client.gd ~17812) against the six attributes gear
can actually roll:

| attribute    | shown as                        | visible? |
|--------------|---------------------------------|----------|
| strength     | folded into **ATK**             | yes      |
| constitution | folded into **DEF** and **HP**  | yes      |
| wits         | its own **WIT** line            | yes      |
| **dexterity**    | energy pool only                | **NO**   |
| **intelligence** | mana pool only                  | **NO**   |
| **wisdom**       | mana pool only                  | **NO**   |

- [x] **DONE 2026-09-11.** DEX / INT / WIS now produce their own bracket lines, shown RAW the way
      WITS already was. Raw rather than folded because unlike strength (which is just attack)
      each drives several unrelated things — there is no single honest number to fold them into.
      The DETAIL view was already correct; only the inline bracket was short, which is why this
      was invisible to anyone reading the item screen. `_get_tool_comparison_parts` needs nothing:
      tools carry no attributes. All four bracket call sites share the one function.
      `tools/probe/item_comparison_stats.gd` covers it, and asserts STR/CON still FOLD rather than
      going raw, so a later "helpful" edit is caught as a contract change.

- [x] ~~Three attributes produce no comparison line of their own.~~ DEX, INT and WIS are read
      ONLY to compute the resource pool (`RES`), so a ring with +6 DEX and no max_energy shows
      nothing at all — while the same ring with +6 WITS would show `+6WIT`. DEX drives hit
      chance, dodge, initiative, flee and (for most classes) crit; INT is a mage's entire
      ability damage; WIS gates poison resistance. None of that reaches the comparison.
      The generic loop right beside it (`class_bonuses_to_compare`) only covers regen/utility
      stats, so there is no table to add them to — they need their own diffs, folded the way
      STR and CON are where a derived number is more honest, or shown raw where it is not.
      **Watch for the same gap in the other comparison surface**: `_get_tool_comparison_parts`
      and `display_equip_comparison` are separate code paths.

## Phase 2.75 — RANGER CRIT: DECIDED, no conversion (owner 2026-09-11)

Owner: *"No flat damage on crit for the ranger. That's the price he pays for no glancing
blows."*

**Closed.** Crit stays dead for a Ranger's cards and is NOT converted into anything. The
visibility work shipped 2026-09-11 (stat screen, buff strip, card faces) is the whole answer —
the trade is deliberate and the player is now told about it in all three places.

Do not reopen this as a balance change without the owner asking: it was considered and declined.
The three pure-crit companion cards (Hunter's Instinct / Sky Talon / Godsbane) remain worthless
to a Ranger BY DESIGN, and now say so on their face.

## Phase 2.8 — DAMAGE ATTRIBUTION WAS LOSSY (found AND FIXED 2026-09-11)

- [x] **FIXED 2026-09-11: 36% -> 0%.** Two causes. The visible one was a mark recording an INDEX
      before its line was appended, so anything appending in between shifted it; marks now carry
      the TEXT they are written into and resolve by content. The real one was the attach step
      SKIPPING any mark made against a different array — the monster turn builds its own messages
      array and the caller appends those lines into the result, so player-applied poison ticking
      on the monster marked one array while its line ended up in another. Proven by re-injecting
      the foreign-array skip: 41% and a clean fail.

- [x] ~~36% of player actions report less damage than the monster loses.~~
      `tools/probe/damage_attribution.gd` reproduces it: 160 player actions across 40 fights,
      58 of them (36%) where `message_damage` sums to less than the monster's pool moved.
      Monsters that HEAL (life steal, regeneration) are excluded from the run, because those are
      legitimate reasons for the pool to move against the claims and would let it pass falsely.

      Worst observed: the monster lost 243, the lines claimed 41.
      ```
      dmg=0   | poison 1424 (10t)
      dmg=0   | CRITICAL!
      dmg=0   | Power Strike — ...        <- the hit that landed, carrying ZERO
      dmg=41  | Your Bone Servant attacks for 41 damage!
      ```
      The Power Strike is applied (the pool moves) but its mark never reaches `message_damage`,
      so the client cannot attribute it. Consistent runs happen too — it is INTERMITTENT, which
      is why the earlier hand-run of a plain monster came back 428/428 and looked fine.

      **Why it matters.** `message_damage` drives the floating damage number and, for monsters
      the player has NOT learned, the enemy HP bar (via `damage_dealt_to_current_enemy`). A lost
      mark means a hit with no number and a bar that under-moves.

      **The likely cause, to confirm before fixing.** A mark records `at: messages.size()` at the
      moment `_damage_with_detail` is CALLED, and the line is appended afterwards. Anything that
      appends to the same array between those two points shifts every later index by one. The
      "CRITICAL!" line in the sample above is appended by `apply_ability_damage_modifiers`, which
      runs in the same statement.

      **The structural fix is to stop recording an index at all** — attach the damage to the LINE
      (append first, then mark the last entry), so there is no window in which it can drift.
      Adding another guard to the index arithmetic would leave the same class open.

      **NOT yet proven to be the owner's 666/750 report.** That monster was KNOWN to the player,
      so its bar was server-authoritative rather than accumulator-driven. This is a real bug found
      while chasing that one; the two may or may not be the same thing. The HP trace
      (`HP_TRACE_ENABLED`) is still in place for the original.

## Phase 2.95 — SPRITE THE OVERWORLD (owner direction 2026-09-11)

Owner: *"the more I think about it the more I wonder if we can just do sprites for the entire
overworld? ... How will it effect server and client performance? How will it impact the number
of supported players on the server at once?"*

**RE-MEASURED 2026-09-11 against the REAL server world, and it overturns the plan below.**
`tools/probe/overworld_render_cost.gd` builds a live chunk manager and calls the real
`generate_map_display`, then times its parts. The old figures came from a standalone timing with
no chunk manager wired (the caveat at the end of this section said so); they were wrong about
both the size and the CAUSE.

**And the harness was wrong once more, which changes the numbers again (2026-09-11, later).**
The cost probe built a chunk manager but never called `load_npc_posts` - the same call the
server makes at boot. So it measured a world with ZERO NPC posts, the minimap's post scan cost
nothing, and every minimap figure below the first two columns was a figure from a world no
player has ever stood in. The probe now loads them, and the real cost was twice what was
reported. (Sixth instance of the same shape: *check what would make the harness produce this
number* - the first row of every table here has now been wrong twice for harness reasons.)

| per location update, at (40,40) | ORIGINALLY | after the tile cache | after the post bucket |
|---|---:|---:|---:|
| whole call, posts loaded | not measured | **31.1 ms** | **15.6 ms** |
| ...minimap | - | 14.9 ms | 7.4 ms |
| whole call, EMPTY world (the old harness) | 46.7 ms | 15.4 ms | 15.5 ms |
| ...map grid: tile fetch | 11.2 ms | 0.8 ms | 0.8 ms |
| ...map grid: line of sight | 1.6 ms | 1.6 ms | 1.6 ms |
| ...map grid: **building the text** | **1.4 ms** | 1.4 ms | 1.4 ms |
| bytes on the wire | 25,590 | 25,590 | 25,632 |

**So "move rendering to the client" was aimed at 1.4 ms of a 31 ms cost - under 5%.** The cost
was never the drawing. It was two loops that did the same work over and over:
`chunk_manager.get_tile` re-generating every tile and stat-ing the disk for every chunk with no
player edits, and the minimap re-scanning every NPC post in the world for each of its 861 cells.
Both are fixed below and the update is now HALF its cost, with no visual change at all.

**What this means for the two steps.** Phase 1 is still worth doing, but for the RIGHT reasons:
it is the **enabler for Phase 2** (the client cannot draw sprites for tiles it has never been
sent) and it cuts the WIRE (25.6 KB a move, of which the map grid is only 4.7 KB - the rest is
the minimap and header). It is NOT the server-CPU fix; that was the tile cache and the post
bucket, neither of which needed a single line of client code.

- [x] **DONE 2026-09-11 — the tile cache, and the disk stat per tile.** `get_tile` now keeps
      generated tiles (terrain is a pure function of x, y, seed) and remembers chunks that hold
      no modified tiles. 46.7 ms -> 15.4 ms per update; `get_tile` 21us -> 1.5us. MODIFIED tiles
      are still checked first, so a player's wall can never be masked; the cache is capped at
      40k tiles and cleared on a world wipe or a new seed. Probe `tile_cache.gd` (8 checks)
      compares warmed vs cold map output character for character; re-injecting "cache wins over
      modified" fails it. **Server-side only: needs a deploy, no client change, nothing visual.**

- [x] **DONE 2026-09-11 — the minimap's post-proximity loop. 31.1 ms -> 15.6 ms per move.**
      `_generate_minimap` walked 861 cells and, for each, looped over EVERY post point in the
      world (60 posts plus their wing rooms, 146 points) doing a box test before it would even
      look at the tile - ~126,000 comparisons for every step a player takes. The test is a fixed
      +/-10 box, so the points are now filed into a 32-wide bucket grid and a cell looks at only
      the buckets its box can overlap: four, not 146. `is_npc_post_tile` still decides the
      answer; the bucket only decides whether it is worth asking.
      One function, `_near_npc_post`, holds the whole test - the probe calls the SAME function
      the minimap calls, so the two cannot drift into one value in two places.
      Probe `minimap_posts.gd` compares it against the full scan it replaced on all 7,749 cells
      of nine minimaps (557 of them post tiles, so the true branch is exercised too) and demands
      zero disagreements; making the lookup visit one bucket instead of four produces 320.
      **Server-side only: needs a deploy, no client change, nothing visual.**

- [ ] **What is LEFT in the 15.6 ms, if it ever needs attacking again.** The minimap is still
      7.4 ms of it and is now dominated by its own 861 `get_tile` + biome-colour + BBCode string
      work, not by anything with an obvious 10x in it. The map grid is 4.7 KB of the 25.6 KB on
      the wire; the minimap is most of the rest. Phase 1 below is what removes that class of
      cost, by sending data instead of text.

|                          | overworld today (ASCII) | dungeon today (sprites) |
|--------------------------|------------------------:|------------------------:|
| tiles drawn              | 529 (23x23, radius 11)  | 171 (19x9)              |
| rendered WHERE           | **server**              | **client**              |
| server CPU per redraw    | **17.2 ms**             | ~0                      |
| wire per update          | **13,333 bytes**        | 2,287 bytes             |
| client CPU               | ~0                      | 5.0 ms                  |

The overworld already costs ~6x a dungeon step in bandwidth and 17 ms of SERVER CPU per player
per move — while being plain text. `send_location_update` builds it, and 40 call sites reach
that function. At 100 players moving once a second it is 1.33 MB/s outbound and ~1.7s of CPU per
second on a 2-vCPU CPX11. **That is the current player ceiling, and no sprite has been drawn
yet.**

So the cost is not "sprites". It is "rendered on the server".

**THE TWO STEPS, in order. Step 2 cannot start before step 1, and everything the overworld shows
- wilderness, NPC POST INTERIORS, player-built posts, other players, monsters - is step 2's
scope, because they are all tiles in the same grid.**

- [x] **DONE 2026-09-11 — PHASE 1. The map goes over the wire as DATA. 28.2 KB -> 3.4 KB a step.**
      `shared/map_payload.gd` is the wire form and the only definition of what a payload means:
      a PALETTE of distinct cells plus one byte per square, base64'd. 1,390 squares (the 23x23
      map and the 41x21 minimap) come from 21 distinct cells, which is the whole reason the old
      string was 96% repetition.
      **There is one implementation, not two.** `build_map_payload` builds it and
      `generate_map_display` is now literally `MapPayload.inflate(build_map_payload(...))`, so
      the text a player sees and the bytes on the wire cannot describe two different maps. The
      renderers were split into cell producers (`_map_cells`, `_minimap_cells`) that both forms
      consume.
      **The server still decides what may be SEEN.** Line of sight, fog and overlay priority are
      resolved server-side and only the resolved cell is sent - a probe asserts no tile internals
      (`blocks_los`, `encounter_rate`, monster levels) ride along, so a modified client cannot
      look through a wall.
      **Old clients keep working.** The client announces `CLIENT_CAPS` at login; a client that
      says nothing is sent the same inflated string it has always been sent. That negotiation is
      the thing to check by hand, and it is item 11 in the playtest queue.
      Probes: `map_payload_golden.gd` (21 views captured on the OLD code, byte-identical after)
      and `map_payload.gd` (18 checks). **Note the trap that nearly shipped:** the obvious
      round-trip check compares `inflate(build(x))` with `generate_map_display`, which is now the
      same expression - it passed happily with an encoder that corrupted every index. The real
      check compares a decoded grid against the CELLS it was built from; that one fails on the
      injected fault, and so does the golden.
      **Needs a DEPLOY and a client release together** (the saving only lands for clients that
      can read it; either half alone is still correct).

- [x] **DONE 2026-09-11 - the payload carries what each cell IS, which PHASE 2 needs.**
      `_map_cells` now returns TWO same-shaped grids, look and meaning, built in the same walk so
      a cell cannot appear in one and not the other. Terrain cells carry their tile type; overlays
      carry a `!`-prefixed kind (`!player`, `!dungeon`, `!fog`, `!hot:tree`, `!depleted:ore_vein`
      and so on) that can never be mistaken for terrain.
      It rides as `payload.meaning`, deliberately NOT a segment: `inflate` never sees it, so the
      text a player reads is still byte-identical to the golden. Wire cost 3.4 KB -> 4.4 KB, still
      6.4x smaller than the 28.2 KB string it replaced.
      **Deriving the type back out of a colour and a glyph was the alternative, and it would have
      been a second copy of the render table waiting to go stale.**
      Probe: 153 terrain cells checked against `chunk_manager.get_tile` at the same coordinates;
      making them all claim `empty` fails it.
      Still open from PHASE 1: the spectate path (`watch_location`) sends the old string, and the
      string building is still spent for clients that cannot read a payload.

- [x] **DONE 2026-09-11 — cosmetic VARIANTS show on sprites, not just in ASCII art.** Owner:
      *"all monsters have variants that change what their ASCII art looks like (like lime ones, or
      two tone red and blue, etc.) How difficult would it be to put a tint or effect on their
      monster sprites?"* Not difficult - the data (`appearance_color` / `_color2` / `_pattern`)
      was already on the wire and only the ASCII art read it.
      `DungeonComposite.tinted()` keys the baked floor out FIRST (the same border-connected key
      `over_prop` uses), tints only the creature's pixels, and supports all ELEVEN patterns the
      ASCII art uses, by the same names. This is the fix for the rule that used to read "never
      tint a floor-backed sprite" - true of a `color=` tag, which stained the ground three
      separate times; false per-pixel.
      Live on: dungeon MONSTERS, the companion following you underground, and companions on their
      Sanctuary cushions (one helper, `_companion_tinted_sprite`, maps a companion's
      `variant_color/2/pattern` onto the same tint).
      **Owner: the tint belongs "everywhere pretty much"** - the remaining surface is the
      OVERWORLD, which has no sprites yet, so it joins in Phase 2.95 PHASE 2 (noted in its scope).
      Probe `monster_tint.gd`: 16 checks including "not one floor pixel moved" and a rendered
      comparison sheet; bypassing the tint fails it. A cached tint costs 1us.
- [ ] **SPRITE SCALE across the game (owner direction 2026-09-11, while reviewing the sprite
      Sanctuary):** *"This makes me also wonder if we should increase player, companion, and
      monster sprite sizes in the overworld and dungeon as well in the future. I kind of like the
      look of the player being a bit larger than the companions. It might make more sense to have
      larger monsters in dungeons and the companions always be a bit smaller than the player."*
      So the rule to carry into Phase 2 here and into the dungeon: **player > companion**, and
      **dungeon monsters larger** than today. The Sanctuary shows the mechanism: the room is one
      composed image and figures are overlays that can span cells (`sanctuary_room.gd`
      `overlay_cells`), so a sprite bigger than its cell is solved. What it costs in the dungeon
      is the monster art: `monster_floor32` is a ~0.5x reduction of the Time Fantasy originals,
      so bigger dungeon monsters should be re-baked from the originals rather than enlarged.
- [~] **PHASE 2 — sprite it, as a client-only concern. LARGELY DONE 2026-09-11.**
      All 67 tile types and all 7 map overlays are real Raven art; `client/overworld_room.gd`
      composes the grid into one image and the client draws slices of it; the player stands on
      it as a figure. Every failure falls back to the text map - art missing, no meaning grid,
      renderer refusing - because a map that will not draw is worse than one made of letters.
      **Still open:**
      monster figures on the overworld at the owner's scale rule, and the dungeon entrance
      hover (which waits on the Phase 3 tooltip fixes - same surface).
      **DONE since:** the settings toggle, other players and everyone's companions as figures
      wearing their variant tint, and the ZOOM inside a post (half the width at double the size,
      so the panel does not jump, with the post's own floor under it instead of the biome).
      Probe `overworld_render.gd` renders the real world and checks the header is byte-identical
      to the text form, so nothing above the map can shift.
      Measured on the real viewport rather than extrapolated from the dungeon:
      **529 inline images = 10.40 ms** per redraw; making every tile hoverable costs
      **+0.10 ms**, i.e. free. That is **1.1% of one client core** at one move/second, 4.2% at
      four. Comfortable.
      The dungeon's compositing + `take_over_path` cache carries over unchanged.

      **What still needs designing** (do not just copy the dungeon):
      * the overworld carries far more per-cell state — biome, weather, fog of war
        (`explored_tiles` is per-player), roads, posts, dungeons, corpses, bounties, other
        players, PvP sacks. The sprite POOL and its cache need a plan; the dungeon's ~11 props
        do not generalise.
      * the map header and legend stay text.
      * `radius 11` is the default but weather and blindness shrink it — the renderer must not
        assume 23x23.

      **Do NOT sprite it server-side.** Measured: the same grid as server-built BBCode is
      **35,665 bytes** against today's 13,333 — a 2.7x wire increase on top of unchanged CPU.
      That would cut the player ceiling rather than raise it.

      CAVEAT on the 17.2 ms: measured standalone, without a live `chunk_manager` wired, so the
      production path may differ. Confirm against the real server before committing to Phase 1's
      payoff figure — the DIRECTION is not in doubt, the magnitude is worth re-checking.

- [ ] **PHASE 2 SCOPE — what "sprite the overworld" has to cover** (2026-09-11, after the
      Sanctuary shipped and posts turned out to be overworld tiles):
      * **Wilderness tiles** - terrain, roads, water, structures. The GROUND varies by biome
        (plains, forest, mountain, swamp, snow, desert); most props do not.
      * **EVERY GATHERABLE gets its own sprite.** Owner 2026-09-11: *"We will want sprites for all
        of the gatherables as well if that wasn't already expected."* That is `tree`, `stone`,
        `ore_vein`, `dense_brush`, `herb`, `flower`, `mushroom`, `bush`, `reed`, `cactus`,
        `ice_bloom`, `swamp_lily`, `mountain_herb`, `brambleberry` - fourteen, several of them
        biome-specific, and they are what a player is actually hunting for on the map.
      * **REAL ART, NOT GLYPHS.** Owner 2026-09-11, on seeing the glyph fallback: *"We should
        have enough sprites that glyphs shouldn't be needed."* So the glyph bake is the last
        resort for a tile not yet cut, not the plan. **ALL 67 DONE (2026-09-11).** Every tile type has real art from the Raven
        packs - fourteen gatherables, six biome grounds, water, roads, walls, the post stations,
        and every piece of post decor. `empty` and `void` deliberately have none: empty IS the
        biome ground and void is a tile outside your sight, so both draw the ground and nothing
        over it. The glyph baker stays as the fallback for anything added later, and currently
        bakes nothing.
        Pipeline: `tools/tileset_contact_sheet.py` (a sheet with row/column numbers, and
        `--map` for an opacity map), `tools/bake_overworld_tiles.py` (the (pack, row, col) table
        and the cutting), `tools/preview_overworld_tiles.py` (composes every tile over every
        biome ground, which is what caught three real mistakes).
        **Rules learned here:** pick cells off the OPACITY MAP, never off the rendered sheet;
        a Raven tree or station spans several cells, so cut the block and shrink it; and a
        ground-class tile must be fully opaque or the biome bleeds through its corners.
      * **67 tile types in all** (`TILE_RENDER`), so the resolver needs a COVERAGE probe that
        calls it on every one rather than a table someone eyeballs. This is the `.png.png` lesson:
        v0.9.761 shipped with all 53 dungeon monster sprites broken because the table was checked
        and the lookup was never called.
      * **NPC POST INTERIORS** - `wall`, `floor`, `door`, and the station tiles (`forge`,
        `apothecary`, `workbench`, `enchant_table`, `writing_desk`, `market`, `inn`,
        `quest_board`, `blacksmith`, `healer`, `cartographer`, `companion_stable`, `tower`,
        `guard`, `post_marker`). The Raven `interiors` and `craft_stations` packs were bought for
        exactly these, and `tools/bake_sanctuary.py` shows the cut-and-bake pattern.
      * **ZOOM INSIDE A POST** - the owner's older ask, and now clearly a mode of this renderer:
        bigger cells while `_is_npc_post_interior` is true, so a post reads as a room.
      * **FIGURES** - the player, companions, monsters and other players, at the owner's scale
        rule (player > companion; monsters bigger in dungeons), and wearing their COSMETIC
        VARIANT via `DungeonComposite.tinted` (owner: the tint belongs "everywhere pretty much";
        every other sprite surface already does this).
      * **DUNGEON ENTRANCES get a sprite AND a hover.** Owner 2026-09-11, agreeing the density
        work: *"We will also want to make sure the entrances are hoverable and sprited once we
        get all of the overworld spriting in."* An entrance is an overworld tile, so the sprite
        comes with this phase for free; the HOVER is the same surface as the three tooltip
        faults in Phase 3 and should be built on whatever fix those get, not beside it. With
        ~3,150 dungeons in the world (the agreed density) the hover is not a nicety - it is how
        a player tells an H4 from an S9 without walking onto it. `sanctuary_room.gd::overlay_cells`
        already solves a figure larger than its cell: the room is one composed image and figures
        are overlays that may span cells. Reuse it rather than writing a second one.
      * **What NOT to redo**: the Sanctuary is finished and is its own screen; it does not become
        part of this.

## Phase 2.9 — v0.9.769 SHIPPED + MAP RESET EXECUTED (2026-09-11)

v0.9.769 is live (7 assets, gate passed, running server hash verified against the local build).
The map was reset on the live server the same night.

**Reset outcome, verified on disk:** kept 11 accounts, 17 characters (max level 12, 69 gear
items) and 183,962 Valor across 10 accounts; moved 16 of 17 characters to the Crossroads (the
17th is an ORPHAN file no account's `character_slots` references, so it is unreachable in game
and was correctly skipped); kept all 5 corpses, none of which needed moving — every one landed
on `empty` ground under the new seed; regenerated 60 posts; cleared the market, all chunk
deltas, and every dungeon instance. New seed 349942589444.

A backup sits at `~/pb-backup-pre-worldreset-*.tar.gz` on the server (601 entries, 82 character
files, 485 chunks) with an `at` job scheduled to delete it 2026-09-13 02:43. If the new world
turns out to be bad, restore it BEFORE that job runs.

- [ ] **Two things the reset exposed that are worth remembering.**
      1. `generate_posts` could not place a single post, for ANY seed — fixed the same night. It
         had been invisible for as long as it has existed because nothing regenerates posts in
         normal play; the live world's 60 were made before the water check was added and simply
         persisted in `npc_posts.json`. **Any generator that only runs at world creation is
         untested by definition** — the reset is now the only thing that exercises them, so run
         it on a scratch world after touching one.
      2. `wipe_all_chunks()` and `clear_all_market_data()` both existed, both documented
         themselves as wipe support, and both had zero callers. Worth a sweep for other
         half-built capabilities: a function nobody calls is a feature nobody has tested.

## Phase 3.0 — LIVE PLAYTEST REPORTS, 2026-09-10 (owner, one session)

Eleven reports in one sitting. Six are fixed and committed; the rest are recorded here with what
was established, so none of them restarts from zero.

**Fixed this session** (see git log): monsters hidden behind the companion; a KO'd companion that
kept following; a companionless player trailing corridor floor; lamps going out when anything
stood on them; the dungeon repainting over the death screen and the [L] log; the Sanctuary
checkout failing silently and losing the player's selection to a refresh; Shrine / Elite Den /
Jackpot Gamble art; and six glyph tiles baked as the font's missing-glyph box.

- [x] **SOLVED 2026-09-11 — the shield WORKS. What failed was that nothing said so.** Owner:
      *"Cleave cycling says it gave 6 shield. Combat log says Kobold attack and deals 16 damage to
      which my healthbar is now missing 16. If the shield did something we should specify since it
      looks like it never existed."*
      **Measured before changing anything**, as this entry demanded ("do not guess a third time").
      Driving real rounds through the real combat manager:
      * a cycled ward of 60 against an 11-point swing → absorbed in full, 0 HP lost, and the line
        already said so;
      * a ward of **6** against a 20-point swing → **absorbed 6, 14 landed, ward spent to 0**.
      The owner's numbers were correct and consistent the whole time: the "16 damage" in their log
      is the figure AFTER absorption, and their health fell by exactly that. The live
      `[FFANOMALY]` detector — added last session for precisely this — has **never fired**.
      **So the mechanic was never broken, and all three earlier theories were wrong**: it was not
      a copied dict, not resolution order (both paths cycle BEFORE the monster turn — 4968 < 5081
      on the ability path, 2490 < 2508 on the attack path), and not a lost grant.
      **The real fault was presentation, and it was half-fixed already.** A FULLY absorbed hit
      names its absorber in the line ("attacks — Forcefield absorbs 46 — no damage taken!") because
      of a 2026-09-10 fix whose own docstring reasons that a hover "keeps the log to one line per
      action... but at ZERO it fails... nobody hovers a zero to find out." A PARTIAL absorb fails
      for exactly the same reason and was left on the hover: "deals 16 damage" beside a 16-point
      health drop is indistinguishable from having no shield at all, and **nobody hovers a number
      that looks ordinary.** It now reads *"The Kobold attacks — shield eats 6 — and deals 16
      damage!"*, still one line.
      Probe: `cycled_shield.gd`. Re-injection (back to hover-only) fails it.
      **An instrument defect of my own, worth recording:** the probe first read
      `process_monster_turn`'s output from `messages` and got an empty list, which read as "the
      shield said nothing" — a false positive against the game. That function returns its text
      under `message`, singular. CLAUDE.md Pitfall #9, hit while investigating a report that was
      itself about a missing message.
- [x] **SOLVED 2026-09-11 — same cause as the re-farm and the lingering "D".** Read off the
      live server log, not reasoned about: the owner re-entered a personal instance that had
      ALREADY been completed in an earlier session, so its saved grid still held the FINAL_CHEST
      and its saved monsters still held the boss marked dead. Completion is now recorded on the
      instance itself (`completed_at`), which the reload prune, the despawn sweep and the
      entrance lookup all already keyed off and were never told.

- [x] ~~A dungeon completed with no boss in it. Owner: *"I just did a T1-1 Goblin Dungeon and
      the chest was just sitting there on the last floor I didn't have to fight a boss to get it
      to appear"*, then, correcting my first theory, *"I didn't fight a boss as there wasn't
      one."* It happened TWICE, so it is systematic, not a rare roll.
      **Ruled out by measurement, not by reading:** the boss placement search. I replayed
      `_find_monster_spawn_position` against 3 generated boss floors, 2000 runs each — 0 failures
      (the boss floor is 64x64 with ~11% walkable, so 100 random darts effectively always land).
      **Also ruled out:** my own theory that the boss was killed unrecognised. The owner says
      there wasn't one, and that outranks the theory. (The boss WAS invisible as a boss — that is
      a real bug, fixed separately with the ring — but it is not this.)
      **Still unexplained**, and the three completion paths all read correctly on the page:
      boss victory (`server.gd` ~6869), stepping on an EXIT while on the last floor
      (`_advance_dungeon_floor`), and the final-chest open/skip handlers.
      **Instrumented rather than theorised a third time** (2026-09-10): spawn now asserts the boss
      floor got exactly one boss and WARNs otherwise — it previously appended nothing and said
      nothing on a placement failure — and completion logs which floor the player was on, of how
      many, and whether any boss is still alive, flagging "completed WITHOUT killing the boss".
      Read those two lines from the next run before touching anything.

- [x] **DONE 2026-09-11.** All 20 monster traits moved into one table (`MONSTER_TRAITS`) with
      a description each, wrapped in `[url=]` so they explain themselves; the Champion/elite got
      a banner with live `role_multipliers` numbers; and every empowered prefix in a monster's
      NAME is hoverable on both the combat log and the nameplate (which had no hover listener at
      all). Probes: `monster_traits.gd`, `empowered_hover.gd`.

- [x] ~~Make variant names and traits HOVERABLE. Owner 2026-09-10: *"We should also consider
      making variant names hoverable so players can see what they do (swift, weapon master,
      champion, venemous, etc.)"* Two different things are being named there and both want it:
      the monster VARIANT baked into the name ("Venomous Orc", "Skeleton Champion") and the
      TRAIT list under it ("Regenerates", "* WEAPON MASTER *").
      **Now cheap, and it was not before.** The trait line has ONE emission point,
      `generate_encounter_text`'s `notable_abilities` in combat_manager.gd — and as of
      2026-09-10 all six scroll-grantable traits go through it (three used to be missing
      entirely). The hover idiom already exists and is used four times over: `[url=<detail>]`
      plus `meta_hover`, as on dungeon monsters, floor loot, theme tiles and card damage
      formulas. So this is: give each entry a one-line description, wrap it in the existing
      `[url=]`, and let the existing tooltip do the rest.
      Do the TRAITS first — they are a closed list in one function. Variants are prefixed into
      the monster's name string, so they need the name split before they can be wrapped, which
      is the fiddlier half.

- [x] **DONE 2026-09-11 — the bar was right, the gate was right, and neither was VISIBLE.**
      Owner asked and hedged: *"I may have been moving too fast though."* They were not.
      Nothing here was broken. The bar's tween is 0.3s, it reads `current_hp` directly, and it is
      held on purpose — since 2026-09-02 `update_player_hp_bar` waits on `_coop_playback_pending()`
      (solo included) so HP cannot drop before the line explaining the hit. Input has ALSO been
      refused during playback since 2026-09-04 (`_combat_input_gated`, applied in `trigger_action`
      and `_on_combat_card_played`).
      What nobody had measured is how LONG that lasts. Real rounds driven through the real combat
      manager, priced at the client's own pacing constants (`tools/probe/hp_bar_timing.gd`):

      | monster | worst round | playback |
      |---|---|---|
      | Giant Spider | 10 messages | **4.55s** |
      | Wolf | 10 messages | **4.55s** |
      | Skeleton | 8-10 messages | 3.65-4.55s |
      | Goblin | 4 messages | 1.85s |

      So for up to **4.55 seconds** the cards rendered at full colour, the press was swallowed in
      silence, and nothing said why or how to skip. That is the whole report: not a lagging bar,
      an invisible rule.
      Fixed by making the existing rule legible — no mechanic changed. All three card-slot
      builders fold `_combat_input_gated()` into `enabled`; the combat panel's hand renders gated
      cards as uncastable (the state it already had) and swaps its deck/discard line for
      *"Round playing… press [Space] to skip ahead"* — the fast-forward has existed all along in
      `acknowledge_continue`, it was simply never advertised at the moment a player wants it.
      Driven from ONE tick in `_process`, not from each enqueue site (there are several: solo,
      co-op, flock chains, fast-forward) — a gate that is right at only some of them would teach
      players the dimming means nothing. Deliberately NOT keyed off `in_combat`, which is cleared
      at combat_end while the round is still animating; that is the exact trap `_combat_ui_busy`
      exists for and six bugs walked into before.
      Re-injection: removing the dimming fails 3 of the probe's 13 checks.
      **Correction worth keeping:** my first pass read `send_combat_command`'s body, found no
      playback check, and reported "in SOLO nothing gates the press". Wrong UNIT — the gate is
      one level up, in the two callers. The probe now checks those, and says so.
- [x] **DONE 2026-09-11 — Tier(letter) + Rank(number), `shared/power_rank.gd`.** Owner
      2026-09-09, raised in the same message as the companion-multiplier audit and lost under it;
      never answered or filed until the owner asked for it again on 2026-09-11:
      > *"the Tier and subtier are confusing, we should probably rename them Tier and rank."*

      **Decided with the owner, 2026-09-11:**
      - Ladder **H G F E D C B A S** — nine letters for nine tiers, and exactly ONE S. Owner:
        *"too many S's, we need an alternative on that."* Extending DOWNWARD instead of stacking
        SS/SSS gives nine distinct letters and leans on school-grade intuition (F fails, A is
        top); H and G are the two starter bands, S the single apex.
      - **Both halves ascend.** The owner first asked for rank 1 = best, then chose ascending when
        it was pointed out that a letter climbing toward S beside a number falling toward 1
        reproduces the exact "two numbers running opposite ways" problem being fixed. Rule:
        later letter wins; same letter, higher number wins.
      - That choice had a happy consequence: `sub_tier` is ALREADY 1-9 ascending, so **rank IS
        sub_tier**. Nothing inverted, nothing migrated, and no build can show a mix of directions.

      **Owner's condition:** *"only if we can make it clear to the player what is better than
      what... Maybe even a star or symbols to help might work."* A letter ladder is not
      self-evident and was not assumed to be. Three affordances, all built:
      - `color()` ramps every label by DANGER, reusing `POST_TIER_COLORS`' vocabulary
        (green safe → red extreme → purple world's edge) that players already read on the map —
        so the label inherits a meaning rather than teaching a new one.
      - `pips()` renders position as a bar (`E` → `▰▰▰▰▱▱▱▱▱`), answering "how far along am I"
        without knowing a single letter.
      - `hover()` spells out the whole ladder with the current tier marked, which end is which,
        and the within-tier rule — on every label in a surface with a meta handler.
      - Plus a generated **TIER & RANK help topic**.

      **Done at the display layer, data untouched** — `tier`/`sub_tier` are unchanged on disk and
      on the wire. All 26 sites that built `T%d-%d` now route through one formatter: `label()`
      plain for `Button.text` and log lines, `tag()` coloured for BBCode panels with no meta
      handler, `rich_label()` hoverable for `display_game`. Server logs carry BOTH notations so
      existing greps still work.

      **Two things found while doing it, neither assumed:**
      - **Companions reach rank 9, dungeons stop at 8.** Fusion caps at 9 (`server.gd` L15594 /
        L15863, every stable panel's `max_sub_tier`), while `get_sub_tier_for_distance` clamps to
        8. A `RANKS = 8` formatter would have silently collapsed the single best companion rank in
        the game into the second best, on every surface at once. Takes the wider domain.
      - **My first help page hand-typed the ladder, the colours and the level bands** — a second
        copy of three constants in the one place a confused player goes. Replaced with a generator
        that reads all three from source; the probe now fails if a band or letter is typed in.

      Probe: `tools/probe/power_rank.gd` — tests ORDERING as behaviour, not string shape.
      Re-injection of the three rejected designs (rank-1-best, the SS/SSS ladder, the 8 cap)
      fails 9 of its 24 checks.

      **FOLLOW-UP DONE 2026-09-11, same session.** Owner: *"Let's do dungeons all the way up to
      the top rank. Also, ensure every companion surface is covered so we no longer see the old
      TX-X system."*
      - **Dungeons now reach rank 9.** `get_sub_tier_for_distance` went 1-8 → 1-9 and
        `get_sub_tier_level_range` slices each tier band into 9 segments instead of 8. The
        CEILING did not move: the top rank still ends exactly at the tier's max level, because
        the last segment ends at `min + 9*(range/9)` just as it used to end at `min + 8*(range/8)`.
        Probe asserts both ends of every tier, and that all nine ranks actually occur across
        20 000 spawn rolls with no gap and nothing outside the range.
        *Honest note on balance:* at a given distance the rank is now drawn from `p*8` rather than
        `p*7`, so difficulty-per-distance rises by roughly 2%. That is well inside the ±10pp band
        CLAUDE.md says to judge against, and it is a MONSTER-side change, not a player-side one,
        so it does not invalidate the reference-player curve and no refit was run.
      - **Every companion surface converted.** 122 prose replacements plus ~40 targeted ones
        across 14 files. The probe now fails if `T%d-%d`, `T8.8`, `Mixed T9` or `sub-tier`
        reappears on any of twelve surfaces, and names the file.
      - **Two stale facts found while converting, both pre-existing:** the help text said Same
        Type "caps at sub-tier 8" while the code has capped at 9 since v0.9.495; and the capstone
        fusion was called **"Mixed T9"** producing a "Tier 9 companion" when it actually consumes
        tier-8 rank-8 companions and yields RANK 9 of the same tier. It reads **Mixed A9**
        (A8 → A9) now, which is what it has always done.

      **THE FOUR-LADDER COLLISION — RESOLVED 2026-09-11.** There were actually **five** tier
      ladders in player-facing text, all using the same word and the same bare numbers, so
      "Tier 5+" could mean five different things depending on the sentence:

      | ladder | steps | vocabulary |
      |---|---|---|
      | monster / dungeon / companion | 9 × 9 | `H G F E D C B A S` + rank 1-9 |
      | trading post | 7 | Core · Inner · Mid · Mid-Outer · Outer · Extreme · World's Edge |
      | consumable / material | 9 | Minor … Master · Divine · Mythic · Primordial |
      | gathering node | 9 | none |
      | equipment | 9 | none |

      **THREE OF THE FIVE ALREADY HAD NAMES** — `POST_TIER_NAMES`, `CONSUMABLE_TIERS`,
      `TOOL_SUBTYPES`, all shipping. Nothing needed inventing; the text had simply stopped using
      vocabulary the game already shows on the map and on the items themselves. So the rule is:
      the lettered ladder keeps the word "tier"; the named ladders use their names; the two
      nameless ones keep numbers but must NAME THE LADDER ("gear tier 5+", "node tier 1-2"),
      because the ambiguity was always the bare noun, never the digit.
      Probe: `tools/probe/tier_vocabulary.gd` fails if any live player-facing surface says a bare
      "Tier <n>" again.
      **Patch notes are excluded on purpose** — `display_changelog` is a historical record of what
      shipped in a given version. Rewriting it would falsify the record, not fix a label.

      **A REAL DIVERGENCE found while doing it, and it needed a design answer, not a rename:**
      monster tiers and dungeon tiers are DIFFERENT ladders below tier 6 — monster tier 1 is
      L1-5, dungeon tier 1 is L1-12; they converge from tier 6 up. Companions and eggs carry the
      MONSTER tier, dungeons carry the DUNGEON tier, and the ladder help page was printing dungeon
      bands beside every letter — contradicting the Bestiary on the one page a confused player
      opens. The page now shows letters and pips only (the ORDERING, which genuinely is shared)
      and says the levels depend on what carries the label. The Bestiary keeps its own monster
      bands and now carries letters.
      **Still open, and it is a balance question rather than a text one:** should those two tables
      be reconciled? Nine tiers with two different level meanings is a trap for whoever tunes them
      next.

      **Two stale facts corrected, both pre-existing:** the *Trial of Blood* title read
      *"Defeat 1,000 Tier 8+ monsters (Level 250+)"* — the tracker gates on `monster_tier >= 8`,
      and tier-8 monsters are L2001-5000, so the level claim was wrong by 8× and is gone. And
      `server.gd` built a fusion message as `(T%d-9)`, an old-notation pair the first sweep's
      `T%d-%d` search could not see; it goes through `PowerRank.tag()` now.

      **`Divine` names both consumable tier 7 and a rarity-1 companion variant. Checked, and it
      is safe** — the two live in unrelated dictionaries and nothing does a name→value lookup
      across them. The one place that did (a per-name variant multiplier table) was deleted on
      2026-09-03 for exactly this class of reason; its replacement derives from rarity. Owner:
      *"I'm fine with Divine on both as long as it doesn't cause bugs."* It does not.
- [~] **LIKELY SOLVED 2026-09-11, awaiting one confirmation.** Almost certainly the same cause as
      the bossless dungeon and the re-farm: the owner was re-entering a personal instance that had
      already been completed, which KEEPS its original sub-tier and skips the whole
      `if instance_id == "":` branch — and that branch is where the sub-tier inherit lives. So the
      tile advertised its own depth while the instance kept the one it was born with. Completion
      is now stamped on the instance, so a finished run can no longer be re-entered.
      The entry diagnostic is still in place; confirm on the next fresh dungeon and close it.

- [x] ~~A dungeon still opens at a different depth than the tile advertised.~~ Owner: *"On the
      overworld this said it was a T1-2 Forgotten Crypt. I entered and it is a T1-7."* This is the
      SECOND report; the 2026-09-08 inherit was supposed to end it and reads correctly on the
      page. A diagnostic now logs, at entry, what the tile resolved to and what the instance got,
      flagging both failure shapes by name (shipped 2026-09-10, no behaviour change).
      **Next step is to read that log, not to theorise again.** The shape to expect is
      `tile=NONE`: `_get_dungeon_at_location` finding nothing at the player's feet even though
      the entrance panel had just printed a sub-tier from the same call, after which the depth
      falls back to a distance roll.
      **The second half of this is FIXED (2026-09-11).** The dungeon LIST matched an instance by
      dungeon_type ALONE and took the first hit in DICTIONARY ORDER — no owner, completion or
      distance filter — so the sub-tier in the name, the recommended level band AND the map
      coordinates the player then walked to could all describe a different dungeon: one already
      finished, one belonging to another player, or simply the far side of the map. That alone
      reproduces "said T1-2, entered a T1-7" without any entry-path fault at all.
      Fixed as the CAUSE rather than a third patch: three sites were separately answering "which
      instance of this type is the relevant one" and two of the three had the right predicate
      while the list had none. They now share `find_dungeon_instance()`, which owns the four
      rules — skip completed, skip other players' personal runs, prefer your OWN live run at any
      distance, else nearest — with a `world_only` flag for the Cartographer, whose question is
      about a 'D' on the map and so cannot be answered by a personal instance.
      Probe: `dungeon_instance_match.gd`, calling the real finder against a synthetic instance
      table rather than reading its source — the fault was never in what the code SAID, it was
      in which row it picked. Re-injecting the type-only rule fails 6 of its 10 checks.
      **Still open: the entry-path half.** Read the DUNGEON-ENTER diagnostic from a fresh run
      before theorising again.

- [x] **DONE 2026-09-11 — the kennel shows the rank AND can inspect.** Owner, in passing:
      *"it doesn't list its current subtier in that screen or let you inspect them"*. Both halves
      are done: the rank landed with the ladder work (tag + pip bar on every card), and the kennel
      now has a full Inspect overlay on its right-click menu.
      **It reuses the ONE builder.** The overlay renders
      `client_ref._build_companion_inspect_bbcode(c)` — the same text the Companions screen shows,
      with the stats, the combat card and the Power figure — rather than growing a second copy of
      that screen. A private copy is exactly how the two would drift, and the variant multiplier
      being wrong for 93% of variants began as precisely that kind of copy. The probe asserts the
      kennel restates none of the content itself.
      A refresh while the overlay is open re-renders it if the index still resolves and drops back
      to the grid if it does not, so a release cannot strand the player looking at a companion
      that is gone.
      **Found while doing it — the OTHER half of the dead-hover class.** The Companions screen's
      `_inspect_text` had **no `meta_hover_started` listener at all**, so every hoverable stat
      label added to that screen earlier today rendered as a link and did nothing. The "Frenzied"
      report was the mirror image: a listener present on a control set to `MOUSE_FILTER_IGNORE`.
      Both panels are wired now, and `hover_reachable.gd` covers both shapes — the listener-on-
      IGNORE sweep it already did, plus an explicit check on the labels known to emit `[url=]`,
      since "does this label ever receive markup" cannot be answered statically.
      Probe: `kennel_inspect.gd`. Re-injection (a private copy + both listeners removed) fails 4.
- [x] **DONE 2026-09-11 — RECALL.** Owner chose *"Add Recall on the Sanctuary screen"* once the
      flow was spelled out: at character select, a registered slot reading "In use by A" can be
      recalled, which returns the companion's LIVE state to the slot and leaves A with no active
      companion on its next login. The Stable deposit keeps working. Refused while A is logged in
      or saved mid-fight, because the running copy would keep fighting with a companion the
      house already lists as home. If A no longer exists the slot is freed from the house's own
      copy — the orphan shape reported 2026-09-04, now self-healing from the screen.
      One strip helper (`_recall_companion_from_character`) clears the same three fields the
      Stable deposit clears, plus the roster mirror, matched by `house_slot` or by id for legacy
      saves. Probe `companion_recall.gd`: 19 checks on the real helper and the wiring;
      re-injection (active companion not cleared) fails 1. **Unplayed** — needs a look at the
      companions page with a checked-out slot before it ships.
      Original ask: *"should we make a way for
      players to be able to send a checked out companion back to the sanctuary? Or maybe players
      should only be able to checkout companions on character creation?"*
      For the record, depositing already EXISTS in game: `handle_companion_stable_checkout`
      refuses with *"Deposit your active companion first"*, so a Companion Stable can take one
      back. What does not exist is a way to do it from the Sanctuary screen at character select,
      which is where the owner was. So the question is really whether the kennel screen should
      gain a Deposit, rather than whether returning should exist at all.

## Phase 3.4 — the CYCLE VALUE (deck-width arc, owner direction 2026-09-10)

Owner: *"make cards with mechanics that make you actually want to grow your deck to a larger size
instead of the way it currently is where it benefits to keep the deck small."* Weighed Slay the
Spire against **Dune: Imperium**, and Dune won on the owner's own three points.

**Why thin wins today, precisely.** Hand is 3, so a given card is available about `3/N` of the
time — 60% at a 5-card deck, 30% at 10. Every card in a curated five is good, so a sixth is pure
dilution. No amount of card QUALITY fixes that; the arithmetic has to change.

**Why not Slay the Spire.** StS also rewards thin decks — its strongest runs are 10-15 cards — so
copying it does not invert anything. It also runs an energy-per-turn economy; ours is a variable
share of a pool plus a per-class engine, so its cost curve does not transfer. Owner raised both.

**Why Dune: Imperium.** The cards you do NOT play pay a smaller benefit as they cycle.
  * **No hand-size change**, which is what has historically skewed the combat scene, broken the
    monster ASCII and cut off the screen. Hand stays at 3; nothing in the layout moves.
  * **We already dump the entire unused hand every action** — that IS Dune's reveal step, already
    built and animated, and nothing read it.
  * **A card with a cycle value is never a dead draw**, so adding it costs less than a normal
    card. That is the dilution maths inverted at the root.

- [x] **The hook — BUILT 2026-09-10, UNRELEASED.** `_cycle_unplayed` pays out cycle values, called
      from BOTH places that dump the hand (playing a card, and a basic attack — hooking one would
      pay when you cast and stay silent when you attack). Five effect types: engine / shield /
      heal / resource / chip. The four existing dungeon cards carry one as proof.
      **OPT-IN ON PURPOSE**: only companion/dungeon cards can hold a `cycle` block, so the
      reference player the monster curve is calibrated against is unaffected and NO chain is owed.
      Making it universal would be a global player buff and would owe the full 25 minutes.
      Verified by probe: fires on both paths, and a class-only hand pays exactly nothing.
- [x] **Reveal as CARD UPGRADES — BUILT 2026-09-10** (owner: *"we could take advantage of card
      upgrades and make these types of reveal options show up in that pool as well"*). Three
      KIND_ANY upgrades — Foretold (engine), Held in Reserve (ward), Smouldering (chip). This is
      the better half of the opt-in: a dungeon card has to DROP, whereas an upgrade is something a
      player builds toward on a card they already run, and it costs a milestone. It also reaches
      CLASS cards, so every player can have it without a lucky drop.
- [x] **Clarity — the reveal is ON THE CARD FACE, not behind a confirm step.** With a hand of
      three you play one and cycle two, so each card stating its own reveal makes the whole trade
      legible at a glance — Dune reads exactly this way — and it costs nothing on every turn of
      every fight. Face and payout are derived from the SAME two sources (card data + the
      player's picks) so they cannot disagree. Verified end to end: face said "cycles: 20 ward",
      two unplayed copies paid exactly 40.
- [x] **PLAYTESTED AND SHIPPED in v0.9.767 (2026-09-10).** Faces read `cycles: 38 ward` /
      `cycles: 122 damage`, both Bulwarks cycled and paid exactly 38 each, Venom Fang played for
      its stated 122, and the upgrade route worked too (`Blast` showed `[cycles: 29 ward]`).
      The design question came back QUALIFIED rather than yes: *"it will very much depend on what
      upgrades hit the players cards. If you get one with a good cycle ability you will likely
      want to keep it in."* So the pull is real but CONTINGENT on the upgrade you draw — which is
      precisely why the rarity finding above is the gate on this arc rather than more cards.
- [x] **DONE 2026-09-11 (local, unplayed) — party CONFIRM step.** A party action is shown first (*'Lock in Forcefield on Bob? Space confirms, Q picks again'*); Space, the card's own key pressed again (the buff-picker idiom), or the Confirm button sends it; Q returns to the hand. Sits AFTER the buff target picker so the confirm can name the target. Solo untouched — the gate is one line inside the party block. Probe `party_confirm.gd` (18 checks; re-injection of a missing reset fails 1). Playtest queue item 7. PARTY has no un-submit, and that is where a confirmation step is actually needed.
      `_party_submit_action` returns early if `submitted_this_round` — a one-way door, so a
      misclick is unrecoverable and you wait out the round. Owner asked for a confirmation step in
      solo AND party; recommending it only for party, because solo already shows the result
      immediately and the card face now carries the reveal, whereas party makes you commit and
      wait. Adding a confirm to solo would tax every turn of every fight for information that is
      already on screen.
- [ ] **THEN the 53-dungeon card content.** The owner chose full coverage, but that decision
      predates this design — cards should now be authored WITH cycle values, so the content pass
      waits on the model being confirmed.

- [x] **SHIPPED v0.9.768 (2026-09-10) - the dungeon ROOM pass.** Per-room floors from 7 packs
      and per-room decor from 7, room IDENTITY via connected components, the rim rule changed from
      outline to SUPPORT, two-cell props (whole lampposts), loot corner-brackets in rarity colour,
      hoverable loot, the consumable sprite, and dungeon LIGHTING at 62% ambient with lamps.
      Plus the 3x3 room fix the owner caught in play, and the player-facing "a wall blocks your
      path" message corrected to "solid rock" - dungeons have not drawn walls in a long time.
      Server redeployed for the loot-hover payload and verified by hashing the RUNNING process.
      All 7 assets live; launcher endpoints answer 200; 804 remote refs audit clean of restricted
      art.
      STILL UNVERIFIED and shipped on code review, unchanged from v0.9.767: party equipment
      rewards and leader logout/permadeath. `party3` sets both up in one command.

## Phase 3.45 — SPRITE INTERIORS (owner direction 2026-09-10, NOT previously captured)

Owner, on buying the Raven Fantasy collection: *"I eventually would like to make inside of posts,
player sanctuary, and player posts use sprites. Not sure how feasible that is though since it
would require our overworld to consist of sprites as well as the current ASCII."* And on the
dungeon split: *"keep our dungeon corridors using what we currently do but make all of the actual
rooms out of sprites from those packs."*

This was discussed across two sessions and never reached the list. Recording it because the packs
are now bought, unzipped and licence-cleared, so the blocker is design rather than assets.

- [x] **ANSWERED 2026-09-11, then CORRECTED the same day — and the correction moves work between
      arcs, so read it before planning either.** The question was whether spriting interiors
      forces the overworld to become sprites too.
      * **The SANCTUARY and a DUNGEON ROOM: no.** Each is its own screen (`_render_house_map()`,
        the dungeon canvas), so both were spritten without touching the overworld. Sanctuary done.
      * **An NPC POST: YES, it is the overworld.** Checked in the code rather than assumed:
        `npc_post_database._place_stations` stamps a post's walls, floor and stations into the
        WORLD CHUNKS as ordinary tile types (`wall`, `floor`, `forge`, `market`, `inn`,
        `quest_board`...), and `world_system._is_npc_post_interior` just asks the chunk manager
        whether a tile belongs to a post. A player walks into a post on the same map, in the same
        renderer. There is no post-interior screen to sprite.
      * **So post interiors are not a separate job: they are the overworld job** (Phase 2.95),
        and they arrive with it. "Zoom the map inside NPC posts" is the same thing seen from the
        other side - a render MODE of the overworld renderer (bigger cells while inside a post),
        which only exists once that renderer is client-side.
      The first version of this entry said posts were a separate screen. That was wrong, and
      acting on it would have built a post-interior screen the game does not have.
- [x] **RECORDED — the assets are ready and better than what we have.** Every Raven pack ships the SAME
      tileset pre-rendered at 16, 32, 48 and 64px, so a 64px cell draws at native resolution with
      zero scaling — sharper than the current dungeon floor, which is a 16px tile upscaled 4x.
      178 of 190 files sit on a clean 16 grid. `interiors` covers post interiors, `cozy_home` the
      sanctuary, `craft_stations` the forge and workbenches we already have, and
      `green_dungeon` / `miners_cave` / `the_underworld` the dungeon rooms. They also ship RPG
      Maker autotile sheets (`RF_*_A4` walls, `A5` floors, `B`/`C` objects), which is free
      information about which cells are floor and which are wall.
      One anomaly: `the_underworld` sheets are 654x366, NOT a multiple of 16 — it has padding the
      others do not. Check before using it as a grid.
- [x] **MEASURED 2026-09-10 — cost is not a reason to hesitate.** Client cost scales with CELLS ON
      SCREEN, not with how many tiles are owned: a room built from sprites costs the same as a
      corridor built from sprites. The SERVER has no idea sprites exist (not one `.png` reference
      in `server.gd` or `shared/`), so none of this touches concurrent player capacity. The two
      things that WOULD cost: a second draw layer per cell (doubles the inline images), and pck
      size — 6.6MB unzipped, negligible.
- [~] **FIRST SLICE DONE 2026-09-11 (local, unplayed) — the SANCTUARY is sprites.** The room takes
      the main canvas (29x19 cells at 32px, it fits whole at 1080p) and the Sanctuary text moves to
      the side panel, the dungeon's split. `client/sanctuary_room.gd` composes the room ONCE per
      layout into one image - seamless plank floor, brick walls with windows, and furniture at
      its own pixel size (gold chest = Storage, statue on a blue rug = Upgrades, cushions =
      companion slots, teal cushion on a green rug = Stable, open door = exit, plus a shelf,
      lamps, fire pit, barrel, crate) - and hands each 32px region to the text grid via
      `take_over_path`, so multi-cell objects need no row-split logic. Pieces baked by
      `tools/bake_sanctuary.py` (Raven interiors + cozy_home; untracked, in the manifest).
      Floor chosen by MEASUREMENT after two screenshots failed (stripes, then a framed-panel
      grid): only the centre plank cell (14,1) tiles with no seam. Verified in-game walking onto
      the chest and opening storage. Probe `sanctuary_room.gd` (27 checks; a missing piece fails
      2); `--buildverify` + release gate assert the art ships. ASCII map is the fallback.
      **Owner's first look (2026-09-11), all done the same day:** companions on their cushions
      (registered and at home; a checked-out one leaves its cushion empty), a soft gold ring on
      every INTERACTABLE object and none on decoration, the player at 2x the raw sprite (two
      cells tall), animation (companions cycle 3 idle frames on a 0.45s timer, the player walks
      through its walk frames and stands when idle), companions at 1.3x, the second cushion row
      moved to row 5 so figures do not overlap, and a **MIRROR** station: click any character
      look to set the ACCOUNT's Sanctuary look (`house_set_avatar`, stored on the house,
      validated against the shared `BattlerPools.all_ids()`). Probe now 24 checks.
      **Next:** NPC post interiors (which also covers "Zoom the map inside NPC posts").
      Original: Slice it the way the dungeon was sliced, which worked: one interior end-to-end
      (the sanctuary, since `_render_house_map()` exists), screenshot, iterate — then posts. The
      DUNGEON ROOMS are a separate problem with its own entry below; do not bundle them in.

### Dungeon rooms from the Raven packs — a DIFFERENT problem to the interiors

Owner, 2026-09-10: *"keep our dungeon corridoors using what we currently do but make all of the
actual rooms out of sprites from those packs."*

**This was first filed as a third slice of the interiors work, which was wrong.** "What we
currently do" for corridors is ALREADY sprites — the darkcave pack. So this is not
ASCII-versus-sprites like the interiors are. It is **two art packs meeting at a doorway**, and the
question is whether their palettes belong in the same room. That is a coherence problem, and it
does not exist in the interiors case at all.

- [x] **DONE in v0.9.768 — the room pool was picked by MEASUREMENT (`bake_room_floors.py`, contrast-gated), not by name.** Palettes compared in HSV against the
      darkcave corridor sheet (2026-09-10), because two greys with different casts look identical
      in an RGB average and wrong on screen:
      | pack | hue gap | value gap | sat gap |
      |---|---|---|---|
      | **shroom_chasm** | **0.006** | **0.009** | 0.154 |
      | **miners_cave** | 0.075 | 0.156 | 0.034 |
      | `green_dungeon` | 0.176 | 0.210 | 0.061 |
      | `the_underworld` | 0.332 | 0.108 | 0.030 |
      The pack literally named **green_dungeon is one of the WORSE matches** — brighter and
      greener, it would read as pasted in beside our corridors. `shroom_chasm` is near-identical
      in hue and brightness and `miners_cave` is both close and thematically a cave. This is the
      same trap the tile pass already hit once by picking a sheet cell by eye.
      `the_underworld` is worst on hue AND its sheets are 654x366, not a multiple of 16.
- [ ] **The brightness gap may be a FEATURE, not a defect.** darkcave sits at value 0.45; most
      Raven packs are 0.57-0.66. Rooms would read as brighter than the corridors leading to them
      — which is what a lit room off a dark passage should look like. Decide deliberately whether
      to lean into that or flatten it; do not correct it by reflex.
- [x] **DONE in v0.9.768 (room identity via `label_rooms`, one pack per chamber). Room VARIETY — DECIDED 2026-09-10: unique and fun beats coherent.** Owner, walking the
      first build: *"we will probably want more variety to the rooms... We have plenty of assets
      to make a huge variety of rooms once we get these working properly."* Then, asked whether a
      room's look should follow the DUNGEON THEME or vary within a floor: *"I'm less concerned
      with if the room looks like it fits in with the dungeon and much more concerned that they
      look unique and fun. The more the better since it will lead to more variety and
      exploration, seeing things no other players have before."*
      **So: vary room-to-room WITHIN a floor, from as wide a pool as we can build.** A mushroom
      chamber next to a mine is the goal, not the failure mode. Note this is the same instinct as
      the card-upgrade rarity item above — *"ones their friends have probably never seen"* — and
      it should be built the same way: a wide pool with genuinely uncommon entries, not a uniform
      shuffle where everything shows up by the third dungeon.
      **The architectural consequence, which the current code does NOT satisfy.** The renderer
      knows whether a cell IS room floor; it does not know WHICH room. Per-cell hashing is right
      for breaking up a floor texture and wrong for this — it would speckle four looks through one
      chamber instead of giving each chamber one look. Rooms need an IDENTITY: a connected-
      component pass over room cells, labelled once per floor and cached beside the existing room
      mask, so every cell of a chamber hashes to the same pack. That is a contained addition to
      what already exists, but it must land before any packs are wired in or the first attempt
      will look like static.
      Assets are not the constraint: 20 packs, each shipping 16/32/48/64px plus RPG Maker
      autotile sheets that NAME which cells are floor, wall and object.

- [~] **THREE LAYERS per room — the owner's design, 2026-09-10. Layers 1 (floor) and 2 (decor) SHIPPED v0.9.768; only layer 3 (walls / rim tint) is open.** *"If for each room we were to
      pick a random pack for the floors, a random pack for the walls, and a random pack for decor
      items that would add 3 layers of variety to make some interesting rooms I believe. We could
      even do doors or chests and things to break it up."*
      **This is the right shape and it is worth saying why.** Twenty packs authored once gives
      20 x 20 x 20 = 8,000 room combinations for the cost of three lookups. The goal — *"seeing
      things no other players have before"* — is reached COMBINATORIALLY rather than by authoring
      eight thousand rooms, and it is the same answer as the card-upgrade pool: width plus
      independence, not more hand-made content.
      **The one hard constraint is LEGIBILITY, not taste.** The owner already ruled that coherence
      does not matter (*"less concerned with if the room looks like it fits in with the dungeon"*),
      so a snow wall around a lava floor is a feature. What is NOT acceptable is a floor and a wall
      close enough in colour that a player cannot tell where the walls are — that is not a bold
      combination, it is an unreadable room. So combinations should be gated on MEASURED CONTRAST
      between the three layers, not on anyone's taste. The HSV palette-distance tooling written to
      choose the room floor already does exactly this measurement and can be reused: reject a
      pairing under a contrast floor, allow everything above it.
      Sequencing, cheapest first, each visible before the next starts:
        1. **Floor per room** — needs only a pack list; `label_rooms` already gives room identity.
        2. **Decor per room — DO THIS BEFORE WALLS.** Measured 2026-09-10, after floors shipped:
           every one of the seven pool packs ships a 768x768 RPG Maker "B" object sheet, which is
           **2,304 object cells each**. Decor is what makes a room read as a mushroom cave rather
           than a mine; walls are only the frame. It is also the layer with by far the best asset
           support, and it reuses the existing prop scatter and the compositor unchanged.
        3. **Walls per room — POORLY SUPPORTED, and that is a measurement not a guess.** Only
           **2 of the 7** pool packs (`green_dungeon`, `winter_forest`) ship an A4 WALL sheet; the
           rest carry floors (A5) and objects (B) only. Scanning their mixed tilesets for a
           wall-like cell was tried and the results were weak — flat blocks, and `shroom_chasm`'s
           best candidate is a treeline silhouette, not a wall face.
           There is also a design cost nobody has weighed yet: the current rim is mostly BLACK
           with rocky edges, which is what makes the map read as carved-out space rather than a
           walled grid (the owner's Azure-Dreams call). A solid pack wall would box rooms in.
           Cheaper option worth trying first: TINT the existing rim per room. It keeps the carved
           look, needs no wall art at all, and the room mask already exists. Note the repo rule
           against `color=` on floor-backed sprites — the rim is not floor-backed, but the art
           gate scans for that pattern and would need to know the difference.
- [ ] **More variety when it is wanted: the OTHER packs, and MULTI-TILE decor** (owner,
      2026-09-10, after the three layers landed): *"If we need more variety we can still look at
      the other sprite packs we have for more Floors, walls, and decor or even expand to
      multi-tile decor."*
      **`tilemap_pack` is the cheapest expansion available and is currently unused for rooms.**
      Its `FreeTileMap.cs.reference` NAMES every index: **12 floors** (`Floor0-5`,
      `FloorRoom0-5`), **26 walls** (`Wall0-25`) and 6 rugs, with `paper_tiles_16x16.png` and a
      `TownTileMap` enum on top. Naming matters more than count here — every Raven cell had to be
      found by scanning, scoring and then LOOKING, and two of the top-scoring "floors" still
      turned out to be water. A named index skips all of that.
      It is also the answer to the layer the Raven packs could not supply: only 2 of 7 shipped a
      wall sheet, and this one has 26 named walls. If per-room walls are ever wanted, start here.
      **Caveat:** `tilemap_pack` is licence-UNIDENTIFIED and untracked for that reason
      (`docs/ASSET_LICENCES.md`). Identify it before building on it.
      **Multi-tile decor is the same problem as TALL PROPS, not a new one.** A 16x32 lamppost and
      a 2x2 shrine both need one object to span two grid cells, and the compositing layer for that
      already exists (`dungeon_composite.gd`) — what is missing is the ROW SPLIT: `prop_for` and
      `decor_for` return one path per cell and have no notion of an object claiming two. Doing it
      once serves both, and the half-lamppost that shipped in the props pass is the reminder of
      what happens when a two-cell object is treated as one.

- [x] **DONE 2026-09-10 - floor LOOT is bracketed, which unblocks the decor pool.** Owner:
      *"we could always put a small border around floor loot to help differentiate it from
      decorations."* Corner brackets rather than a closed frame: a rectangle round every pickup
      turns two adjacent items into what looks like a table of cells, and it is heavier than the
      job needs. Drawn at runtime by `DungeonComposite.bordered`, cached, no new assets.
      The colour is the item's OWN colour straight off the floor-item payload - rarity for
      equipment, kind for everything else. That colour already existed and was only ever visible
      on the GLYPH fallback, so this puts information on screen that the sprite path had been
      throwing away, rather than inventing a code for players to learn.
      `tools/probe/loot_border.gd` covers the two silent failures: brackets in the wrong place,
      and brackets lost when the sprite is composited onto a room floor - which is the order the
      renderer actually uses.

- [x] **DONE 2026-09-10 - decor pool widened from 3 packs to 7.** The corner brackets on floor
      loot are what made it safe: jars, crates, pots, a kettle, ingots, skulls and a box are all
      usable scenery now that real pickups are marked. 13 tiles -> 31.
      The CHICKENS stayed out, and no border fixes them - a live animal reads as a MONSTER, and
      monsters are drawn as floor sprites here too. See the food-source item below, which is a
      better use for them than scenery.

- [x] **DONE.** Floor loot emits `[url=loot:<x>,<y>]` and resolves through the same
      `meta_hover_started` popup as monsters and theme tiles. Verified present in client.gd.

- [x] ~~Floor loot should be HOVERABLE (owner, 2026-09-10): *"I wonder if it makes sense to make
      loot mouse hoverable to see what it is now?"* Yes, and it is nearly free: the dungeon
      already hovers monsters and theme tiles through one idiom (`[url=...]` +
      `meta_hover_started` -> popup), floor loot already carries its full `item_data` on the wire,
      and the loot cell is already an `[img]` that could be wrapped in a `[url]` exactly as the
      monster cell is. The brackets say "this is a pickup"; hover would say WHICH pickup, which is
      the natural next question and the one the colour alone cannot answer.

- [ ] **Chickens (and animals) as a dungeon FOOD source** (owner, 2026-09-10): *"One argument for
      the chickens is they could be a food source that can be found in the dungeon so they can use
      it when they rest."* This turns a rejected asset into content, and it lands on a system that
      already exists - resting underground consumes food from the pouch, and running dry is a real
      pressure on a long run.
      It also fits the dungeon design: a floor that can feed you changes how far you push, which
      is the same lever wandering monsters pull. Open questions for whoever picks it up: is it a
      floor-loot KIND (bracketed like other pickups), a passive creature you catch, or a tile you
      interact with? `farmlands_v3` has 12 chicken frames, so there is art for any of the three.

- [ ] **Walls only where they explain the space** (owner, 2026-09-10): *"It may be better if only
      the spaces below a corridor show those (almost as if they are holding up the corridors) and
      then walls would only be placed above spaces in a room, helping people differentiate the
      rooms from the corridors even further."*
      So the rim stops being "wherever floor meets void" and becomes DIRECTIONAL: rock below a
      corridor cell, rock above a room cell, void everywhere else. Two things recommend it beyond
      the look — far less rock on screen, and the rim itself becomes a legibility cue that says
      corridor-or-room before you read the floor at all. It also composes with the three-layer
      plan rather than competing: less wall on screen means a per-room wall tile matters less,
      which may retire the wall layer entirely.
      Cheap to try: `_dungeon_touches_floor` already finds the rim and would become a directional
      test. The owner has offered to judge sample rooms, so build the samples rather than
      guessing at it.

        4. ~~Doors and chests at the seam~~ — **DROPPED 2026-09-10.** Owner: *"We may not really
           need doors."* Agreed on reflection: the seam is already marked twice over by work that
           landed first. A room has its own FLOOR MATERIAL, so crossing the boundary is already a
           visible change, and the directional rim means corridors and rooms carry rock in
           different places. A door would be a third cue for a distinction that two already make.
           It was also the worst-supported: the only real door art is in `free_floor32`, which
           comes from `tilemap_pack` whose licence is UNIDENTIFIED, and the only Raven pack with
           doors has trapdoors.

- [ ] **Where is the SEAM?** A room entrance is a hard transition between two packs in adjacent
      cells. Options: a doorway/threshold tile from the room pack that reads as belonging to
      both; a one-tile border of rubble; or accepting the cut. Needs to be looked at on screen,
      not reasoned about — the same way the prop occlusion question was settled.
- [x] **DONE in v0.9.768 (`DungeonTiles.label_rooms`, cached per floor). The renderer needs no change; telling a room from a corridor was the actual work.** A room
      cell is one inline `[img]` exactly like a corridor cell — only the sheet it indexes differs.
      But the distinction does NOT survive generation: `_carve_room` and `_connect_rooms` both
      write `TileType.EMPTY`, so by the time the grid reaches the client a room floor and a
      corridor floor are the same number. (Checked, after first writing here that the generator
      "already knows" — it knows while carving and then throws it away.)
      **Do NOT add a TileType.ROOM for this.** Every walkable check in the client and server tests
      against EMPTY/CLEARED, so a new walkable type would have to be added to each of them, and
      that is the shape of change that leaves one site behind.
      **Derive it CLIENT-SIDE from the grid instead — no protocol change, no new tile type.** A
      corridor is one tile wide and a room is not, so counting walkable neighbours separates them:
      a cell with walkable neighbours on both axes is room floor, a cell walkable along one axis
      only is corridor. That is the same trick `_dungeon_touches_floor` already uses to find the
      wall RIM, so it is an idiom in this renderer rather than a new one. Cache per floor; the
      grid only changes when the floor does.

## Phase 3.46 — 2D EFFECTS for dungeons (owner raised 2026-09-10, NOT previously recorded)

Owner: *"I noticed there is documentation in `client/sprites/darkcave Add CRT effect` to make a
CRT effect in Gamemaker. Not sure if doing this type of thing in GoDot is possible or would be
beneficial to Dungeons or not."* Then, after the room work: *"are there any types of 2D effects
(lighting or others) that you think would be good for our dungeons?"*

Answered in conversation at the time and never written down, which is the gap the backlog audit
was supposed to close. Recorded now with the feasibility actually checked rather than guessed.

**The infrastructure already exists.** `client/shaders/low_hp_vignette.gdshader` is a canvas_item
shader doing a radial falloff, attached to a full-rect `ColorRect` with `MOUSE_FILTER_IGNORE` on a
CanvasLayer, driven by `set_shader_parameter`. Anything below is a second use of that pattern, not
new plumbing. There is also `region_tint.gdshader`. So "is this possible in Godot" is settled: yes,
and this project already does it.

- [~] **DECIDED 2026-09-10: torch + lamps, and DARKNESS IS A DUNGEON TRAIT. The default light (62% ambient + lamps) SHIPPED v0.9.768; what is OPEN is the per-dungeon LIGHT LEVEL property and the dark late-game dungeons.** Owner, after
      seeing five treatments: *"I like the 4th one of Torch + lamps but I don't want the dungeon
      to be too dark if players don't have a torch. The only way I'd be open to that is if players
      don't have to micromanage it. Entering dark dungeons all the time would get old. I guess we
      could possibly have some really dark dungeons and torches or lamps as a later game or
      specific dungeon thing though."*
      **That is a better design than the samples asked for, and it is worth naming why.** Making
      darkness a property OF THE DUNGEON rather than a resource the player carries removes the
      micromanagement entirely - there is no torch to buy, light, refuel or forget - while keeping
      everything darkness is good for. It also gives the two-cell lampposts a real job, because a
      lamp only matters where it is dark.
      **The shape:**
        * A normal dungeon is GENTLY lit. Atmosphere, nothing hidden, no new thing to manage.
          Candidate default around 62-75% ambient floor - the owner is choosing from a rendered
          set rather than a number.
        * A dungeon carries a LIGHT LEVEL as a property, the way it already carries a theme, a
          tier and a boss. Most sit at the default; a few are dark.
        * DARK dungeons are a late-game or specific-dungeon thing, where lamps, braziers and lava
          become navigation rather than decoration.
      **Implementation notes, so this is not re-derived:**
        * `low_hp_vignette.gdshader` is the working precedent - canvas_item shader, full-rect
          `ColorRect`, `MOUSE_FILTER_IGNORE`, driven by `set_shader_parameter`.
        * The player is NOT always centred: the viewport clamps at floor edges, so the light
          centre must be passed as a uniform in view space. A fixed `vec2(0.5, 0.5)` puts the
          torch in the wrong place at every edge.
        * Light positions are free - the renderer already knows where tall props and landmark
          tiles are while it draws the grid.
        * `tools/probe/light_samples.gd` + `tools/light_variants.py` regenerate the comparison
          sheets for any future tuning, so the numbers can be re-judged on screen rather than
          argued about.

- [ ] **CRT / scanlines — possible, but I would not do it first.** A `ColorRect` overlay with a
      scanline shader is straightforward and the pattern above shows how. Two honest reservations:
      the game is TEXT-HEAVY, and scanlines over a combat log or a side panel cost legibility for
      atmosphere; and at a 64px tile on a 1080p screen the effect is subtle enough that it may not
      repay the cost. If done: scope it to the DUNGEON CANVAS only, never the whole window, and
      ship it off by default as a setting.
      The GameMaker documentation the owner found is a `.pdf` with subset-encoded fonts - its text
      could not be extracted - so it is a reference for the LOOK, not a recipe to port.
- [x] **SUPERSEDED — the shader route shipped in v0.9.768, so the baked-dim alternative is moot. Cheaper atmosphere worth considering before any shader:** the compositor can already bake
      per-cell variants, so a DIM version of a floor tile is a cached texture rather than a shader
      pass. That is how the existing occlusion and decor work; it would not need a shader at all,
      at the cost of more cache entries. Worth comparing before reaching for GPU work.

## Phase 3.5 — input and accessibility (owner direction 2026-09-10)

Owner: *"we need to add support for players with no numpad on their keyboard. With no numpad they
will have a hard time moving through the world... Ultimately it would be great if we had some type
of controller or phone support as well."* A 2026-08-20 playtest had already recorded that
"non-numpad keyboards need an answer at some point"; it was never written down anywhere actionable.

- [x] **Keyboard parity — DONE 2026-09-10, PLAYTEST PASSED.** Owner confirmed diagonals land
      (including deliberately sloppy chords), taps are not swallowed, held travel is full speed,
      H hunts, and the rebind works. `ARROW_CHORD_GRACE_SEC` stays at 70ms — *"didn't seem laggy"*. The overworld arrow fallback was FOUR-direction only
      (the code said so), so on an 8-way map a laptop player could not take a diagonal at all and
      was slower on every journey. WASD is unavailable — Q/W/E/R/Space are the action bar — so
      diagonals are CHORDS: hold Up+Left for north-west. Owner asked the right question about it,
      *"are we sure it won't fire the movement if one of the keys is hit slightly before the
      other?"*, and without mitigation the answer was no: movement is polled per frame, a frame is
      16.7ms, and a human chord lands 20-60ms apart, so the cardinal fired and MOVE_COOLDOWN
      locked the diagonal out for 150ms. `ARROW_CHORD_GRACE_SEC` (70ms) holds the FIRST step only;
      a diagonal seen inside the window resolves immediately, a release inside it still moves so
      quick taps are not swallowed, and held travel re-reads live at full speed.
      Also: **H hunts** (Hunt was the one action with no numpad-free route at all), opposite keys
      cancel rather than racing, and the movement-keys rebind menu had `start_rebinding("move_4")`
      immediately overwritten by `start_rebinding("hunt")` — so pressing 4 rebound Hunt and WEST
      could not be rebound at all, in the exact menu a numpad-less player is sent to.
      The help popup no longer opens with "the best way to control your character is the numpad".

- [ ] **Controller support (NEXT).** Godot has joypad input built in; a D-pad or stick gives all
      eight directions natively and the face buttons map to the action bar. Scope it as its own
      piece. Note `_on_move_button` already exists as an orphaned 8-way handler with no caller —
      an on-screen pad that was built and removed — and it is the natural target for both a
      controller cursor and touch.

- [ ] **Phone / touch (LATER, its own arc).** Needs a mobile export preset, a touch UI, and a
      layout rework — the three-panel desktop layout does not survive a phone screen. Much larger
      than the other two; do not start it inside another arc.

## Phase 3 — combat UX debt (visible to every player, every fight)

- [ ] **HOVER TOOLTIPS: three faults, reported live 2026-09-11 by the owner.** All three are the
      same surface and should be fixed together, because two of them are almost certainly one
      cause (nothing owns the tooltip's lifetime or its placement).
      1. **A tooltip gets STUCK on screen and never leaves.** Owner: *"I've got a Thorned -
         reflects melee damage box stuck on my screen after hovering a Thorned hobgoblin. It has
         persisted through fights."* Surviving a combat end means the hide path is tied to the
         hover-exit signal alone, with nothing clearing it when the thing hovered is destroyed or
         the screen is rebuilt. **Find what owns the hide, not just this one trait** - a box that
         outlives its own subject will do it again on the next surface that forgets.
      2. **The tooltip opens in the wrong PLACE.** Owner: *"when hovering the underlined Damage
         word on a companion inspect ... the hoverbox appeared way over on the right of my
         screen."* Placement is presumably computed against the wrong control's rect, or against
         the viewport rather than the hovered word.
      3. **APEX is not hoverable and should be.** It appears in monster names like the traits do,
         and every other term beside it explains itself. Owner: *"APEX should be a hoverable term
         in names as well."*
      **ALL THREE FIXED 2026-09-11, and two really were one cause.**
        1. **The stuck box.** `_monster_name_label` was the one surface out of eight connected
           for `meta_hover_started` and never for `meta_hover_ended`, so the popup it opened had
           nothing that would ever close it. Every other label had the pair written out by hand
           on adjacent lines, which is exactly how one came to be missed. There is one
           `_wire_hover()` now and the probe fails if a raw connect reappears.
        2. **"Persisted through fights"** is the OTHER half, and hover-out does not fix it:
           when the LABEL leaves rather than the pointer - combat ends, the scene is rebuilt -
           no hover-out can fire, because there is nothing left to leave. The panel now closes
           the popup when its own visibility drops.
        3. **The misplaced box.** Two faults in one line. The popup's SIZE was read in the same
           frame its text was set, so the clamp that keeps it on screen was clamping against the
           PREVIOUS popup's size; and the mouse was read in the combat panel's canvas space
           while the popup lives under the scene root, which are only the same space when
           nothing between them carries a transform - and this project scales its UI.
        4. **APEX and ELITE are hoverable**, wrapped in the same `[url=]` the trait chips use.
           The apex text carries the real 38% win band read off `APEX_TARGET_WIN`, not a number
           invented for the tooltip.
      Probe `hover_lifetime.gd`; restoring the original one-sided wiring fails it.

- [x] **FIXED 2026-09-11.** The ramp is now ONE computation, `CombatManager.engine_damage_ramp`,
      called by the funnel for both classes and sent as combat state (`engine_damage_ramp`)
      exactly as `finisher_value` is. The client caches and multiplies by it; the probe asserts no
      copy of RANGER_AIM_DMG_PER or BARBARIAN_RAGE_DMG_PER exists in client CODE, so tuning
      either constant cannot desync the card face again. Display-only: no damage changed, no
      calibration run needed.

- [x] ~~EVERY Ranger and Barbarian card understates its damage, by up to 88%.~~ Found 2026-09-10
      while chasing the owner's report on Killing Shot; the finisher was the symptom, not the bug.
      **The cause.** `Steady Aim` (+11% per Aim held) and `Rage` (the Barbarian twin) are applied
      inside `apply_ability_damage_modifiers`, the shared funnel every damaging card passes
      through. The CLIENT card estimate has no knowledge of either — searched, there is no mention
      of Steady Aim in `client.gd` at all. So the face is right at 0 stacks and wrong by
      `stacks x 11%` at every other value: 11% low at 1, 44% at 4, 88% at a full bar.
      The finisher was fixed at the point of report because its value is computed SERVER-side in
      one place (`_finisher_value`). Every other card is still wrong.
      **The fix, and why not a second copy.** Do NOT add the ramp to the client estimate as a
      literal — a client-side copy of a server constant is the shape that caused this whole class
      of bug (see `feedback_one_value_two_places`). Send the ramp as a combat-state value, the way
      `finisher_value` and `assassinate_chance` already are, and have the client multiply every
      damage estimate by it. One computation, one reader.
      **Display-only**: this changes no damage, so it does not invalidate the monster curve and
      does not need a calibration run. It can ship on its own.

- [x] **ADDRESSED 2026-09-11 (visibility) and DECIDED (no conversion).** See Phase 2.75.

- [x] ~~A Ranger cannot crit with abilities, so every crit buff is dead weight for them.~~ Raised
      by the owner: *"does hunter's instinct increase crit chance for abilities on the ranger?"*
      Answer: no, and not because of a bug. The Ranger passive `Steady Hand` sets `no_glance`, and
      the ability crit path reads `if _passive_has_no_glance(character): cc = 0` — the companion's
      crit bonus IS summed into `player_crit_chance` and then discarded. Basic attacks are not
      zeroed, so it still works there.
      That is a deliberate trade (no glances, no crits) and the reliability identity the class was
      given. **The problem is that nothing tells the player.** This game is deck-driven — an
      earlier note in the combat code puts basic attacks at *"~1% of what players do"* — so a Wolf
      companion card advertising *"greatly increased crit chance"* is, for a Ranger, almost
      entirely inert, and there is no way to find that out except by measuring.
      Options, owner's call: say it on the passive's own text and on any crit-granting card when
      the reader is a Ranger; or give `Steady Hand` something to do with crit buffs (convert them
      to flat damage, say) so the stat is not simply voided. The first is honest; the second is
      kinder to a player who already spent the card slot.


- [x] **NOT LIVE — disproved 2026-09-11.** Reproduced the other way: `_get_combat_hand_actions`
      puts an empty slot on R and the hand on 1/2/3 (`R=—, 1=Power Strike, 2=Cleave,
      3=Bull Rush`), for a full hand, a one-card hand and an empty one. The owner's own combat
      screenshots show the same. Fixed at some point without a traceable commit;
      `tools/probe/combat_card_hotkeys.gd` now guards it so it cannot drift back.

- [x] ~~Combat card hotkeys read R, 1, 2 instead of 1, 2, 3~~ (owner, 2026-09-06):
      *"now that outsmart has been removed our card numbers shifted to R, 1, and 2. This is odd.
      It should be 1, 2, 3 still."* No fix commit found in a search of the log since that date, so
      treat it as still live until reproduced. Retiring a card should not renumber the hand — the
      hand is always three cards and should always be 1/2/3 whatever else occupies the bar.
- [x] **DONE 2026-09-11 — it was not repeating, it was WITHHOLDING.** Owner: *"Analyze needs an
      adjustment to show something fresh rather than the same crap."* Asked before implementing;
      owner chose "show more of what it already knows" over rotating or escalating. The card was
      printing FOUR facts — name, HP, damage, and a bare unexplained "Intelligence" — out of the
      thirty a monster carries, so it read as canned because most of what it knew never reached
      the player. It now reports **Defense** (the other half of "how hard is this to kill", simply
      absent before), **Speed**, **Guile** (the same number, relabelled and captioned *resists
      Distract* — it is what Distract rolls against, which nothing said), **Traits** through the
      shared `MONSTER_TRAITS` table so each stays hoverable and cannot drift from the encounter
      line, **Pack** (whether killing it brings friends — purely tactical and previously
      invisible), and **Spoils** (drop chance + XP, i.e. whether it is worth the fight). Probe:
      `analyze_readout.gd`. Re-injection: restoring the old four-fact block fails 9 of 13 checks.
      Two checks were FALSE POSITIVES on the first pass and only re-injection exposed them —
      "the two readouts differ" passed on differing HP alone, and a file-wide search for
      `MONSTER_TRAITS` matched the ENCOUNTER line's copy. Both are now scoped.
- [x] **DONE — and my first verification of it was WRONG (2026-09-11).** I reported "every pair
      shares 4 of 5 cards, differentiation is one slot" and filed it as a design concern. Owner:
      *"Ranger, Ninja, and Grifter all have different starter decks and build different engines.
      There are multiple names for some of these cards that I believe is leading to some of this
      confusion."* Correct. I compared internal IDs; one id shows a DIFFERENT NAME per class via
      `ABILITY_NAME_OVERRIDES` (sabotage -> Ninja "Hamstring", Ranger "Snare"). Measured by what
      the player actually sees:
      ```
      Ranger   engine Aim       Track, Snare, Weak Point, Ambush, Killing Shot
      Ninja    engine Read      Mark, Hamstring, Ambush, Phantom Strike, Assassinate
      Grifter  engine Leverage  Size Them Up, Distract, Sabotage, Sucker Punch, Double Cross
      ```
      Ranger vs Grifter 0/5 shared, Ninja vs Grifter 0/5, Ranger vs Ninja 1/5, three separate
      engines. Thoroughly differentiated. Nothing to do.
      Recorded as [[reference-card-ids-vs-display-names]] — resolve through
      `_ability_display_name` before counting anything player-facing.

- [x] ~~Ranger and Ninja STARTER decks~~ (owner, 2026-09-06): *"They should start with cards from
      their deck that make sense for their intended play styles. Likely just need to swap a few of
      their enabler starter cards with a few they aren't using."* The 2026-09-07 theming pass
      renamed and re-roled cards across all nine kits, which may have absorbed this — but the ask
      was about which five cards a class STARTS with, which is a different thing from what they
      are called. Verify against the current starters before doing anything.



- [x] **"Exposed 995T" — the status chip lied twice, FIXED 2026-09-09.** Found in the 1080p
      capture above, not reported. Two defects in three lines:
      * **999 is a SENTINEL** meaning "rest of this fight" (a monster's curse has no natural
        expiry), and the chip printed it as a turn count. Now `CombatManager.REST_OF_COMBAT_TURNS`
        with a display floor, because the sentinel is decremented every round like any other
        duration — the first version compared against the sentinel itself and so only worked on
        turn one, which the next capture caught as "Exposed -16% 995T".
      * **`bval > 0` dropped negative magnitudes**, so every DEBUFF on the player fell to the
        bare-timer branch. The 2026-09-07 "show the magnitude" fix covered buffs only; a curse
        never said it was -25% defence.
      Reads **"Exposed -25% this fight"** now, verified through the real render path.
      `gm_apply_buff` added so this is reachable on demand — the curse is a 30% roll and three
      capture runs in a row failed to proc it, which is the same verify-by-luck gap
      `gm_spring_trap` closed for traps.

- [x] **Warrior and Mage engine gain shows as a COUNT — DONE 2026-09-09.** Those archetypes drew
      one `+⚡` / `+◈` marker regardless of how much they granted, so they could not show a bonus
      at all. The three branches are now ONE path: the server already computed a per-card
      breakdown for every archetype (`preview_engine_breakdown`, ungated from `trickster` and
      renamed off `read_*`, since a field named for one archetype's engine is how the labels
      drifted before), and the card face draws N pips from it — solid for certain, hollow for a
      chance. War Cry correctly advertises **2** now (its own surge plus the shared +1).
      The finisher exclusion is one list for all three paths, replacing three separate
      `card_name !=` tests of which the Trickster's had been missing for a month.
      **A regression was caught on screen, not in review:** the mage branch reached for
      `_engine_label_text`, which is the TRICKSTER's label, so a Wizard's Blast printed
      "+◈ Read". `update_focus` had always RECEIVED the mage label and never stored it; it does
      now (`_focus_label_text`), so there is one name per engine. `-- enginenames` still 9/9.

      **The 7 "hidden bonus" warnings from `-- cardpromise` are the AUDIT, not the cards.**
      Measured: the only two classes that vary 1-2 are the only two with an engine-feeding class
      passive — the Paladin's Retribution (+1 Conviction per blow taken) and the Sage's Foresight
      (+1 Insight on a round it fails to hurt you). Every class without one measures exactly 1.
      So the extra point comes from the monster's turn and is charged to the card. Isolating the
      card's own share is harder than it looks and was ATTEMPTED AND BACKED OUT: subtracting the
      passive's recorded share leaves a residue (a monster turn can also end a cast early and rob
      the card of its grant), and suppressing the monster turn does not stop Foresight, whose
      condition is "was not hurt". The audit still measures the round, with that interpretation
      written into it, rather than being half-corrected. **The card faces are correct** — these
      cards do not under-report, so nothing here needs fixing on the player-facing side.


- [x] **Card upgrades that did nothing — DOWN TO 3, and the 3 are the ruled-on ones (2026-09-09).**
      Was 8 dead pairs; the item's own diagnosis was wrong on both counts it guessed at.
      * **`vindication` on Judgement was NEVER BROKEN.** The item said the finisher's victory path
        "appears to return before the upgrade block runs". It does not. `-- upgradefit` builds a
        deliberately TANKY monster (`make_monster(40, "normal", 3.0)`) so a card cannot end the
        fight and short-circuit multi-cast upgrades like `relentless` — which also meant nothing
        ever DIED, so a kill-triggered upgrade could not fire on any card in any class. Fifth
        instrument defect in this audit. The last of the six fights is an EXECUTION now (monster
        on 1 HP) and all four `vindication` pairs cleared.
      * **The cost-funnel gap was real, on `refund` not `opening_act`, and bigger than a card.**
        `path_last_ability_cost` is stamped only by `apply_variable_cost`, and Magic Bolt is
        *explicitly excluded* from it (`VARIABLE_COST_TABLE.has(name) and name != "magic_bolt"` —
        it keeps its own arg-driven path). So on the mage's signature card the marker held a
        stale value or zero, and TWO systems read it: the `refund` upgrade AND the talent effect
        `kill_cost_refund_pct`, which a player can spend points on and which silently did nothing
        on the biggest cast in the mage kit. Now stamped at the point of PAYMENT, the one fact
        both cost paths share.
      * **Remaining 3 — `harrying` on Analyze — are the ones the owner already ruled STAY**,
        conditional on the companion and dungeon card passes. Note the Grifter's entry is a
        harness artifact rather than a real gap: `upgradefit` casts one card in isolation, so
        Distract never lands and the enemy is never rattled, but a Grifter DOES hold Distract.
        The genuine gap is the Ranger and the Ninja, neither of whom carries a rattling card.
      `-- upgradefit` is at 3 dead pairs of 1117. **Read its docstring before trusting a run**:
      it has now been wrong FIVE times, and every wrong version produced output indistinguishable
      from a real finding.


- [x] **Character creation was stale — DONE 2026-09-07** (owner: *"Seems like it's not showing the
      correct classes or descriptions and some of the other info is dated."*). Three faults:
      the class button printed the raw id, so the list said "Sage" while the panel beneath it said
      "Oracle"; race passives had THREE copies and two had drifted (Dwarf's Last Stand advertised
      at 25% against a real 34%, the Halfling's +15% Valor attributed to monster kills when it is
      paid on market listings); and the screen predated the per-class engine work, so it pitched
      nine classes on flavour and a passive alone. It now shows "Builds: Rage / Conviction /
      Insight..." and the five cards you will actually hold under their per-class names, all read
      live. `Character.race_passive_for` is the new single source for races.
- [x] **Release perf guards can no longer be lost — DONE 2026-09-07** (owner: *"we need to find a
      solution so this is Always done with every new release without me having to tell you or
      correct it each time."*). `--buildverify` had existed since 2026-09-05 and **nothing ever ran
      it**. `tools/verify_release_build.sh` runs it against a packaged client and exits non-zero on
      a stale build or a missing guard; `max_fps` is now set from code beside vsync, since a
      setting living only in project.godot has no runtime assertion. Mandatory step in CLAUDE.md
      before upload. Verified by watching it BLOCK the stale 0.9.754 build.

- [x] **Buff/debuff visibility — SELF and ENEMY done 2026-09-07.** Party members still to do.
      Three gaps, all of them things the player could not see at all:
      - The **enemy's debuffs from the current card set** were never sent. Sabotage/Hamstring/Snare,
        Distract and Analyze/Track/Mark are most of the Trickster kit, and you had no way to know
        whether one landed or how big it was. Now sent and shown with magnitude.
      - Player buff chips showed **duration only** — "Iron Skin 4T" never said what it was worth.
        Now magnitude and duration.
      - **Most mitigation is not a buff**, so it appeared nowhere: CON grants it from the stat and
        the class engines grant it from banked stacks (Fighter Momentum, Sorcerer Volatility,
        Grifter Read). A Fighter now reads "-54% taken (Constitution 6%, Damage reduction 48%,
        Momentum 5%)". This also makes SPENDING engine stacks legible, since spending gives the
        mitigation up.
      Computed by `player_mitigation_breakdown()` in the combat manager, combined multiplicatively
      the way the damage path actually applies it, so the number cannot drift from the real one.
      `-- statuschips` prints what both sides show.
- [x] **Card-upgrade pick is trackable now — DONE 2026-09-08, owner-confirmed "Looks great!"**
      It was `_ms_order.shuffle()` plus an instant grid rebuild, so the cards TELEPORTED and the
      nine-card preview was decoration. Ported `combat_loot_panel._enter_shuffle`: face-up copies
      glide from where a card sat to where it lands, then seal, so you follow the upgrade you
      want. Reveals are locked for the 0.7s flight (a fast click would land before anything
      visibly moved, reintroducing the exact problem), and the lock clears on OPEN as well as on
      landing, so an overlay closed mid-flight cannot leave it stuck.
      **Client-side, deliberately.** In the loot panel the SERVER owns the prize slots, so the
      swaps must come from the server or the animation lies. Here the client already holds all
      nine upgrades and their text, so it IS the source of truth for the order and animating its
      own permutation is honest. I initially told the owner this needed a server round trip; it
      does not. Do not add one.
      Not done, available if wanted: **peek tokens** (the loot panel's other aid — a rare, limited
      re-show of one face-down card), and staggering the flights if nine at once ever reads busy.
      `tools/test_setup/run.py --ranks=N` hands back exactly N rank-ups for looking at this.
- [x] **FIXED 2026-09-11 — Ranger and Barbarian card faces understated by their engine ramp.**
      Reported by `preview_drift.gd` as "Ambush and Gambit 1.4x"; the cause was wider. The 11am fix
      sent `engine_damage_ramp` as combat state and multiplied it in on the client, but only in the
      client's FALLBACK estimate. In combat the card shows the server's `preview_ability_effect`
      value directly, and that never had the ramp, so every funnel card of a Ranger (Steady Aim)
      and Barbarian (Rage) read low by stacks x 11% / 16%. Measured at 3 stacks: preview 127, dealt
      179. The ramp is now applied in the preview's anchored branch with the same helper the hit
      uses. `preview_drift.gd` gained a Barbarian case and a seed (it flickered run to run);
      26 rows, 0 drift; removing the fix makes 8 rows drift.
      Residual, minor: Magic Bolt at L60 reads 0.83x (card ~17% high), inside tolerance and
      identical on master.
- [ ] **Two stale instruments.** (1) `card_vs_server.gd` reproduces the client's pre-server
      fallback formulas "verbatim", so it prints "LIES" for a path the combat card no longer uses;
      retire it or point it at `_estimate_ability_card_effect`'s server branch. (2)
      `card_upgrade_effects.gd` reports 23 upgrades "not yet wired" from a HAND-TYPED list.
      Several of those (the Reveals, Bulwark, Executioner-family triggers) are wired and proven by
      `upgrade_new_wired.gd` / `upgrade_triggers.gd`. Derive the list from what actually fires,
      or delete the section — a stale list reads as a real finding.
- [ ] **Knight +15% damage and Mentee +30% XP are DEAD — owner's call.** Both are promised in
      the title UI and help, and `get_knight_damage_bonus` / `get_mentee_xp_bonus` /
      `get_mentee_extra_xp_bonus` have no callers. Same shape as `gold_find`. Wire them (a
      player-power change, rare endgame titles only) or remove the promise.
- [x] **FIXED 2026-09-11 — the first-gather tutorial is sent again, and says what really happens.**
      It was only called from three handlers nothing routes to, so no new player had seen it since
      v0.9.369; its text described the retired wait-and-react game. Now sent from
      `handle_gathering_start` and rewritten from the dispatch: mining / logging / foraging /
      shallow fishing are a **16-card scratch-off grid** (2 scratches + 1 per 25 skill, max 8; a
      tool pre-reveals cards); only deep-water fishing is the 3-choice chain.
      **My own mistake, corrected in the same pass:** the help fix earlier today described ALL
      gathering as 3-choice, copied from the main help page's claim without reading the dispatch.
      Both pages now match the code, and `help_topics.gd` checks against the dispatch.
      The three dead handlers (`handle_fish_start` / `handle_mine_start` / `handle_log_start`)
      are still in server.gd; delete them in a cleanup pass.
- [ ] **Buff panel, party half.** Same strip for each party member, plus a STACKING indicator.
- [x] **Card upgrade preview — DONE 2026-09-07.** The estimate counted `power` picks alone while
      the combat manager applied nine more multipliers from hard-coded literals, so five upgrades
      silently moved the real hit while the card kept printing its old number: Overdraw / Reckless
      / Brittle / Heavy Draw each add 25-35%, and **Slow Burn TAKES 25% away** with no visible
      change at all. Both sides now read one table, `CardUpgrades.DAMAGE_MULTS`.
      Conditional upgrades are deliberately EXCLUDED from the printed number and shown as their
      own "Situational: x1.4 foe under 30%" line — averaging a trigger into a flat number is wrong
      in both directions. The rank-up hover now shows the card WITH the pick on it
      ("412 -> 462 damage (+12%)") instead of the abstract "+12% effect", and Power's shrinking
      marginal gain is shown honestly because it rides the tier multiplier rather than compounding.
      `-- upgradepreview` drives the real roller 4000x per upgrade against what the card prints;
      worst gap 0.007.
- [x] **Trickster engine labels forked — DONE 2026-09-07** (owner: *"I'm good with forking it."*).
      All three read "Read" while warriors showed Momentum / Rage / Conviction and mages Focus /
      Volatility / Insight. It was wrong about the game, not just inconsistent: the finisher fork
      gave the three DIFFERENT shapes — the Grifter banks and cashes (Momentum-shaped), the Ranger
      ramps and discharges (Focus-shaped), and only the Ninja gambles on the bypass (Read-shaped).
      One noun for three mechanics. Now **Grifter = Leverage, Ranger = Aim, Ninja = Read** (the
      Ninja keeps the shape name, as Fighter/Momentum and Wizard/Focus do).
      Root cause of why it had nowhere to land: `update_read` was the only one of the three meter
      functions with no `label` parameter, and `read_label` was the only engine label the server
      never sent. Both fixed, so the label lives in one place.
      Swept all seven surfaces; `-- enginenames` now prints what each class is told and PASSES 9/9.
      **Mages have no engine log line on purpose** (2026-09-04, one-line-per-action) — the meter
      carries it; the audit encodes that so nobody "fixes" it later.
- [x] **Stale copy on the path buttons — DONE 2026-09-07.** The Trickster path still pitched
      *"Outwit, evade, or strike critically"* — selling **Outsmart**, retired 2026-09-05. All three
      path pitches now describe the loop the path actually plays. The help page's class overview
      was worse: it listed **Paladin = self-healing** (it is Retribution — Conviction built by
      blows you take) and **Sage = efficient** under its old name rather than the Oracle. All nine
      now name their engine there.
- [ ] **Death replay / shareable combat log.** When a player dies, the chat message carries a
      clickable link to the combat log — ideally a replay — so everyone can see how it happened.
- [x] **Combat layout at 1080p — CONFIRMED FINE, CLOSED 2026-09-09.** Owner: *"needs confirmed
      before we work it. May not be an issue anymore."* Captured the real client at 1920x1080 and
      looked: the combat log, monster art, player/companion panel, card row and action bar all sit
      clear of one another. Nothing overlaps. The 2026-05-28 report is stale — the combat scene has
      been rebuilt several times since. Closed rather than "fixed".
      The capture DID have to be repaired first: the scene spawned the monster at player level + 8
      and a L14 wizard killed it inside the four scripted rounds, so the shot was skipped and the
      question went unanswered. `gm_godmode` protects the player; nothing protected the monster.
      Now level x6, a multiplier so the margin survives future player-power changes.
      Found while looking: the status chip read **"Exposed 995T"** — see below.

- [ ] **Extend UI-scale registration** to the elements that still lack it (action bar, status HUD,
      inventory, market, crafting, sanctuary).

- [ ] **Dungeon level mismatch — BLOCKED, needs a second example.** Owner reported a 1-1 wolf
      dungeon advertising "recommended level 3" while floor-1 wolves were level 6. A real defect
      was found and fixed in v0.9.758 (the warning quoted `min_level`, a static field on the
      dungeon TYPE, while monsters are sized from the INSTANCE and scale per floor). But the
      specific 3-to-6 gap could NOT be reproduced: tier 1 sub-tier 1 computes to a level 1-2 band,
      so something else may also be involved. Owner 2026-09-08: *"something we will need another
      example of since you were unable to find its cause."* Do not guess at a second fix — wait
      for a repro with the DUNGEON NAME, then trace that instance's `dungeon_level`.

- [x] **DONE 2026-09-11 — help screen fixed and pinned by `tools/probe/help_topics.gd`.** All 26
      audited entries corrected after re-verifying each against the code; the main help page, which
      had shown every key binding as `[%s]` because its format string failed on every call, now
      formats; Rage's ramp corrected to +16% on two surfaces. Details and what the audit itself got
      wrong: `docs/design/help_audit_2026-09-11.md`. (Project docs and CLAUDE.md were not swept.)
      Accuracy audit: help screen, project docs, CLAUDE.md (owner, 2026-09-07, partially done
      and never tracked): *"audit project documentation, the help screen, claude files, we need to
      check for accuracy."* A docs pass happened (`bebf7644`) and the help page's vestigial
      ability LEVELS were removed in the same era, but nothing swept the help screen against the
      game as it now is — and this release alone added cycling, changed how upgrades work and
      renamed pages in the admin panel. The failure mode is specific and has bitten before: the
      help page told new players they could not have their finisher until level 100.
      Cheap version: `-- cardnames` and `-- statdesc` already print what each class is SHOWN, so
      diff those against the help text rather than reading both by hand.

## Phase 4 — party (half-built; finish or cut)

- [ ] **Invite window** and **watch-a-teammate's-minigame** — the two remaining Party UI pieces.
- [x] **Party rewards — AUDITED 2026-09-10, the live path is correct.** Read AND probed. The
      simultaneous path (`_end_party_combat_all`) skips only `dead` / `fled` / missing members and
      gives every survivor their own XP, companion XP and an INDEPENDENT loot roll, with
      inventory-full auto-salvage on equipment. `tools/probe/party_rewards.gd` confirms a round
      resolves to victory with both members eligible.
      **A trap was removed while looking.** `_handle_party_combat_victory` — 182 lines of
      plausible reward logic containing `var is_dead = rewards.is_empty()`, i.e. death inferred
      from a missing dictionary entry — had NO CALLERS. It is the old sequential path, superseded.
      It cost me a false alarm within minutes (the probe "found" every living member reported
      dead, because it was asserting on a field only the dead path populates), so it is deleted
      rather than left to mislead the next reader.
      **Still open, and NOT verifiable headlessly**: the payout itself runs server-side and needs
      `characters`/`peers`/`persistence`, so a live two-client run is the only way to confirm the
      equipment actually lands. Also still open: rotate the leader between fights, and splitting
      gathering/crafting rewards.
- [ ] **"Party play isn't working properly"** (owner, 2026-08-26) — no repro captured. ASK for the
      symptom before investigating.
- [x] **Leader logout no longer strands the party — FIXED 2026-09-10, and it was THREE paths.**
      Only `handle_disconnect` cleaned up party state. `handle_logout_character` and
      `handle_logout_account` erased the character and left the player in `active_parties` and
      `party_membership` — so a LEADER returning to character select left the party pointing at a
      leader with no character, with no transfer and no disband. Worse than a stale row, because
      `peer_id` survives character select: the same connection could pick another character and
      keep playing while still registered as leader of a party it had left.
      **The root was not those functions — it was that the rule lived in someone's memory.**
      `tools/probe/exit_paths.gd` asserts it instead: any function erasing a peer from
      `characters` must call `_cleanup_party_on_disconnect`. It immediately found a FOURTH path
      nobody had looked at — **`handle_permadeath`**, which under the game's central pillar is the
      one that matters most: a leader dying for good left the survivors in a broken party.
      Proved by re-injecting a removal and watching it fail (exit 1, naming the function).
      **Not runtime-verified**: `active_parties` lives on the server, which the sim harness cannot
      instantiate, so a live two-client check is still owed.

- [x] **Companion card pass — DONE 2026-09-09** (owner: *"most companion cards are too weak to be
      viable or useful at all"*). Measured first, with a new `-- compcards` audit that casts both
      a companion card and the class's own cards through the real path and compares them.
      * **The real fault was the BASIS, not the multipliers.** Damage came from
        `character.get_total_attack()` — a PHYSICAL stat — so a mage's companion punched like a
        mage. After doubling the raw powers a warrior's card reached 59-84% of the median card it
        displaces while a Wizard's reached 10%; two paths in three could never have had a viable
        companion card no matter how the numbers were tuned. It now takes a share of the level's
        reference HP bar, which is what the companion's ORDINARY attack already uses — class-
        neutral and already calibrated. Result: 360-391 across all nine classes, from 210-481.
      * **A better companion now makes a better card.** Tier, sub-tier and the authored attack
        profile all scale it, read the same way `_process_companion_attack` reads them. Measured:
        fresh hatchling 485, fused apex with an attack profile 1355 — nearly 3x.
      * **The STUN/DISTRACT requirement was already met** and needed no content: `blind` sets
        `enemy_distracted` and `stun`/`timestop` set `monster_stunned`, exactly the fields
        `harrying`/`demoralising` test. Nine cards carry them (Goblin/Harpy/Nazgul blind,
        Gargoyle/Shrieker/World Serpent stun, Siren/Succubus/Cosmic Horror charm, Time Weaver
        timestop). The blocker was only ever that no one would run them. **So the Phase 3
        `harrying` dependency is now satisfied** — a Ranger or Ninja can slot a rattling
        companion card.
      * **No recalibration chain needed**, checked rather than assumed: the simulator's reference
        player never casts a companion card, so the monster curve is blind to them. Worth knowing
        the other way round though — now that they are viable, the reference deck is that much
        less representative of a player who runs one.
      * `-- compcards` reports cost but does NOT score it, and says why: measured at L40 a
        Fighter's Cleave and a Grifter's Ambush cost ZERO (warrior/trickster costs are flat and
        capped — the known resource-economy flaw), so damage-per-point is meaningless for six
        classes of nine. A verdict on that axis was written and removed rather than left to
        produce confident nonsense. It also under-reports bleed/poison DoT, lifesteal healing and
        plunder/tribute rewards, which it does not measure.

- [ ] **Dungeon card pass** (same conversation): *"dungeon reward cards likely need reworked and
      added to add interesting new cards that classes may want to swap into their decks."* The bar
      is a card a player would CHOOSE over one of their five, which today almost none clear. Same
      note as above: some should rattle the enemy.

## Phase 5 — the dungeon arc (the big content direction)

- [ ] **AN H9 COMPANION BEATS A G1 BY ~3x, AND ASCENDING IS A DOWNGRADE. Owner asked for this
      comparison 2026-09-11 and the answer is the bad one.** Owner: *"we may need to compare power
      of companion tier and rank to see if an H9 is weaker or stronger than a G1."*

      **Rank is the whole power axis. Tier is very nearly cosmetic.**
        * HP (`Character.calculate_companion_max_hp`) reads the companion's LEVEL, its species
          profile, its rank, and its variant. **It never reads tier at all.**
        * Damage quality is `1 + 0.06*(tier-1) + 0.05*(rank-1)`. Eight ranks are worth +0.40;
          one tier is worth +0.06. A rank is worth about eight tiers in that term, and infinitely
          more in HP, where a tier is worth exactly nothing.
        * The bonuses a companion grants the player scale on rank ONLY: 1.0x at rank 1 to 2.0x at
          rank 9. Tier is not a factor.
      Same level, same variant: a Skeleton H9 carries ~3.1x the HP of an Orc G1 and hands its
      owner 2.0x bonuses against 1.0x.

      **Tier Ascension is therefore a trap.** Three H companions plus a Catalyst produce one G1
      with rank reset to 1, level reset to 1, and the SAME species bonuses. The player gives up
      the rank multiplier (up to 1.4x HP and 2.0x bonuses) and every level they had earned - and
      level is the entire base of both HP and damage - in exchange for +0.06 on one damage term.
      **It is strictly worse in every case.** This is live.

      **And the check that should have caught it tests a string.** `PowerRank.power_index(tier,
      rank)` exists and defines the right ordering, and `tools/probe/power_rank.gd` asserts
      *"the WEAKEST of a higher tier still beats the STRONGEST of a lower one (G1 > H9)"*. But
      `power_index` is called by **nothing in game code** - the companion screens use PowerRank
      only for labels and pips. So the probe asserts a property of a display formatter while the
      stat code does the opposite. Textbook "verify the FUNCTION, not the ingredients".

      **What it means for the dungeon plan.** The owner's progression - clear H1-3, then H4-6,
      then H7-9, then move to G - only makes sense if G beats H. Today it does not, so a player
      who climbs H to rank 9 has no reason to ever leave it. **Fix the ladder before, or with,
      the dungeon placement work**, or the placement work ships a progression nobody should
      follow.

      **OWNER DECIDED 2026-09-11: make TIER REAL.** Tier multiplies HP and the bonuses granted to
      the owner, not only the 0.06 damage term, sized so the weakest of a tier beats the strongest
      of the one below. Both ladders route through `PowerRank.power_index` so ONE number orders
      all 81 cells and `tools/probe/power_rank.gd` finally asserts a stat rather than a label.
      **CORRECTION to what this note first said: ascension does NOT stop being a downgrade as a
      consequence.** I wrote that before checking. Ascension resets the companion's LEVEL to 1,
      and level is the entire base of both HP and damage - the grade multiplier sits on top of
      it. Three H companions still become one G1 that is far weaker than any of them. Making
      tier real is necessary and not sufficient; **ascension needs its own fix, carrying rank
      and level across**, and that is still open.
      Owner also asked the fair question behind it: *"the alternative is if our current system
      holds and we can make a clear progression path for players that they will be able to
      understand easily."* Worth keeping in view - if tier is made real, the player-facing
      promise becomes simply "further right on the ladder is stronger, always", which is the
      easiest thing to explain and the thing the display already implies.
      **DONE 2026-09-11 - one ladder, `PowerRank.power_mult(tier, rank)`.** Geometric in
      `power_index`, so it is monotonic across all 81 cells by construction: one constant,
      `GRADE_POWER_STEP = 1.30`, says each grade is 30% above the one below and a rank is a
      ninth of the way there. Span H1 1.00 to S9 10.30.
      It now drives companion HP (which never read tier at all), the bonuses a companion grants
      its owner, its abilities, and combat damage quality - the four places that between them
      made an H9 beat a G1. The two rank-only tables it replaced are read by nothing.
      Probe `companion_ladder.gd` checks the STATS through the functions combat calls, at all
      eight grade boundaries, not the label. That distinction is the whole point: the old probe
      asserted "G1 > H9" and passed, because `power_index` was called by nothing in the game.
      **Re-calibration:** run after this, since it changes player power.

- [ ] **A WORLD DUNGEON BUILDS ITS WHOLE INTERIOR AND NOBODY EVER LOOKS AT IT.** Found 2026-09-11
      while costing the owner's *"massively increase the amount of dungeons"*. This is the reason
      dungeons are capped, and the cap is the reason the world is empty.

      `_create_world_dungeon` eagerly generates, for a map marker nobody has entered:
      every floor's BSP grid (~7 floors, ~56x56 each) and ~70 monster entities, each paying a
      full `generate_monster_by_name` roll. That is roughly **520 KB of grid plus ~100 KB of
      monsters per dungeon, ~600 ms of CPU per spawn**, and at the 200-dungeon cap about
      **100-130 MB of resident RAM**.

      **None of it is ever read.** Entering a world `D` calls `_create_player_dungeon_instance`,
      which generates its own fresh grids, and the local `instance_id` is reassigned to the
      personal instance before any floor is touched. I checked that path directly. World dungeons
      are also not persisted (`_save_dungeon_state` skips them) and not stamped into chunks - the
      `D` is a pure per-request map overlay.

      **It is redundant twice over.** `generate_floor_grid` seeds on `(dungeon TYPE, floor)`, not
      on the instance, so every `goblin_caves` floor 2 in the world is byte-identical. There are
      about **370 distinct grids in the entire game**, and the server can be holding two thousand
      copies of them.

      **Every cap and every cache in this area is a workaround for this.** The spawn queue exists
      because bursts cost ~5 s; the check interval went 30 s to 120 s; `_threat_state_cache` and
      `_world_threat_states` exist because scans were iterating 150-450 dungeons per move.

      **The remaining real cost, which does NOT go away by itself:** a player move does roughly
      **three linear scans of every active dungeon** (`get_visible_dungeons` for the map, and
      `_get_threat_zone_dungeon_at` twice). 900 iterations at today's cap, and it grows with
      whatever the cap becomes. Raising the count without fixing this just moves the spike.

      **The order to do it in:**
        1. [x] **DONE 2026-09-11 - the interior is LAZY.** All three world-dungeon creators
           (`_create_world_dungeon`, `_create_world_dungeon_near`, `_ensure_starter_dungeon_exists`)
           now build nothing, and `_ensure_dungeon_interior` builds floors, rooms and monsters if
           anything ever asks. Made lazy rather than deleted ON PURPOSE: deleting would assert
           "nothing reads this", and this PROVES it, because the accessor logs `[LAZY-DUNGEON]`
           whenever it fires. **Watch the live log - if that line appears for a `world_dungeon_*`,
           the interior IS read somewhere and the caller needs finding.** Player instances are
           untouched, and for them the accessor is one dictionary lookup.
           Probe `lazy_dungeon_interior.gd`; re-adding an eager build fails it.
        2. [ ] ~~Cache grids by (type, floor).~~ **MEASURED AND WRONG - do not do this as stated.**
           `generate_floor_grid` seeds itself on `hash(dungeon_id + floor_num)` and plainly means
           to be reproducible, so a cache of ~370 grids looked like the next win. It is NOT
           reproducible: two `Array.shuffle()` calls in `_carve_alcove_spurs` draw from the GLOBAL
           rng and escape the seed, so the same type and floor give a different layout every
           call. Caching today would silently change what dungeons look like.
           **The prior question is a design one: SHOULD every `goblin_caves` floor 2 in the world
           be identical?** The seed line says someone intended yes; the shuffles have delivered no
           for a long time and nobody noticed. Decide that before touching it. (This is the
           measure-before-building rule earning its keep - the cache was three lines from being
           written on the strength of reading the seed.)
        3. [x] **DONE 2026-09-11 - dungeons are indexed by position, and the count is raised to
           what the owner asked for.** A tile index answers "am I standing on one?" in one
           lookup, and 64-wide buckets answer the map markers, the threat cone and the per-post
           threat count. Measured at 3,000 dungeons: a map-radius query is 1.8us bucketed against
           117us scanning, and 400 box queries agree with the full scan exactly.
           Spawning no longer builds a set of every dungeon's coordinates, which was what made
           FILLING a world quadratic.
           **Counts: MIN 150 -> 3000, MAX 200 -> 3300, active cap 300 -> 4200.** The drain takes a
           2 ms frame budget rather than one dungeon per frame, since a spawn is now a placement
           roll and a dictionary insert.
           **The index cannot go stale by accident:** one function creates a dungeon, one erases
           it, and the probe fails if a raw write or a second erase appears. A missed hook shows
           up as a dungeon you cannot walk into or a `D` that will not go away - both silent.
           Probe `dungeon_index.gd`.
        4. [ ] Only then decide whether placement becomes a pure function of (x, y, seed). What
           blocks that is not placement but three pieces of mutable state: `cleared_by` (which
           should be per-character anyway, and is already implicated in a re-farm bug),
           the despawn/threat lifecycle, and the post threat-cap pacing.

- [ ] **PERSONAL dungeons are never cleaned up on logout or death. Owner 2026-09-11:** *"we need
      to ensure we have proper cleanup of those after players logout for so long or their
      character dies so they don't just linger on the map."* **Confirmed, and it is worse than
      lingering on the map.**
      `_cleanup_player_dungeon` is called from exactly two places: quest completion and quest
      abandon. Nothing else.
        * **Disconnect deliberately keeps them** - the handler says so, so a reconnecting player
          can resume mid-dungeon. Reasonable, but there is no timer that ever ends that grace.
        * **Death does not clean them either** - no death path calls the cleanup.
        * **World dungeons get a 24-hour age cull; personal ones get none.**
        * They DO show on the owner's map: `get_visible_dungeons` filters out other players'
          personal dungeons, not your own.
        * And `player_dungeon_instances` is keyed by PEER ID, which is reassigned on reconnect,
          so an entry can be orphaned from the account that owns it and then be unreachable by
          any cleanup that does exist.
      **DONE 2026-09-11.** Owner: *"Personal dungeons cleanup is a must."*
        * Disconnect now STAMPS `abandoned_at` instead of deleting anything, so reconnecting into
          a run still works. `_sweep_personal_dungeons` ends that grace after
          `PERSONAL_DUNGEON_GRACE_SECONDS` (30 min), and caps any personal dungeon at
          `PERSONAL_DUNGEON_MAX_AGE_SECONDS` (24 h, matching world dungeons). Coming back inside
          the grace clears the stamp.
        * Permadeath drops every instance the player owned. `exit_dungeon()` had only ever
          cleared the CHARACTER's side, leaving the instance alive with nothing able to reach it.
        * Instances are found by USERNAME, not peer id, which is what made the orphan possible.
        * A dungeon somebody is standing in is never swept.
        * And `_erase_dungeon_instance` is now the ONE place that knows which dictionaries hold
          dungeon state. There were three hand-written erase lists; the world cull's had fallen a
          dictionary behind and never erased `dungeon_traps`. That is the same "one value, two
          places" shape as everything else on this list.
      Probe `personal_dungeon_cleanup.gd` (24 checks), including that disconnect does NOT erase -
      cleaning up there is the opposite mistake and would break reconnect. Stopping the sweep
      from running fails it.

- [ ] **A DUNGEON TYPE STOPS OWNING ITS GRADE. Owner direction 2026-09-11, and it is the biggest
      of the four.** Owner: *"We do want lower types of monster dungeons to be possible in high
      level areas (example an A5 Goblin Dungeon, or a S2 Kelpie one etc)."*

      Today `tier` is a hardcoded field on the dungeon TYPE, and it decides three separate things
      at once: what the dungeon is called (the grade letter), how strong its monsters are, and
      where in the world it may appear. Splitting a Goblin Caves off from "tier 1" means pulling
      those three apart:
        * **GRADE becomes a property of the instance**, rolled where it spawns, not read off the
          type. Combined with the agreed placement change, the land decides the grade and the
          grade decides the levels - so an A5 Goblin Dungeon is simply a goblin_caves that spawned
          in A-grade country.
        * **The type keeps what it is FOR:** its species, its boss, its egg, its name and colour.
          That is arguably a better Atlas: you hunt a TYPE for the companion it yields, at whatever
          GRADE you can survive. It also gives the Cartography rank-seeking something real to seek.
        * **Monsters scale fine.** A species has no level ceiling - `scale_monster_to_level` will
          build a level-3000 Goblin correctly. **One thing to check before building:**
          `_apply_out_of_tier_bonus` only adjusts a species placed ABOVE its home tier and does
          nothing when it is below, so a goblin in A-grade country gets no correction at all. Find
          out whether that is right or whether under-tier needs the mirror treatment.
        * **`min_level`/`max_level` on the type become advisory only** (they already are, outside
          the dungeon-list UI), and `dungeon_band(tier)` starts being asked about the INSTANCE's
          grade rather than the type's.
      **This supersedes part of the placement item above:** placement no longer follows a type's
      fixed tier, it follows the instance's rolled grade. Do them together.

- [ ] **DUNGEONS GET A RARITY. Owner 2026-09-11:** *"Dungeons should have a rarity moving
      forward."* The data is already written and has never been read: `spawn_weight` sits on all
      53 types with values from 50 down to 1, appears about forty times in
      `dungeon_database.gd`, and **nothing in the codebase reads it**. Selection is
      `dungeon_types[randi() % dungeon_types.size()]` - uniform over every type in the game.
      Two axes to decide between, and they are not the same thing:
        1. **Type rarity** - a Kelpie Marsh is a rarer sight than a Goblin Caves. That is what
           `spawn_weight` was authored for; making the picker weighted is a few lines.
        2. **Grade rarity** - a rank 9 is rarer than a rank 1 in the same country. That belongs
           with the grade roll in the item above, not with `spawn_weight`.
      Owner probably means both. Worth confirming which, because (1) alone leaves every grade
      equally common and the climb the owner described has no scarcity in it.

- [ ] **A DUNGEON CONTAINS EXACTLY ONE SPECIES, and the Atlas advertises otherwise.** Found
      2026-09-11 answering the owner's question about how monster tiers work in dungeons.
      Every regular monster on every floor is generated from `boss.monster_type` - one string. A
      Goblin Caves is 100% Goblins, and even the map letter is that species' first character.
      `monster_pool` (`["Goblin", "Giant Rat", "Kobold"]` and so on for all 53 types) is read by
      **one line in the whole codebase**: the Dungeon Atlas UI, which shows it to the player. So
      the Atlas promises three species and the dungeon delivers one. Either the pool should drive
      spawning or the Atlas should stop claiming it - and the first is almost certainly what was
      meant, since the data has been sitting there unused.

      **OWNER DIRECTION 2026-09-11, which settles it:** *"I would be fine with dungeons having
      other monsters of the same tier spawning within them (more rare, less likely than the main
      dungeon monster/boss type). The floor loot eggs could also be of any of the monster types
      that spawn in that dungeon, the boss should still be of the dungeon type and the guaranteed
      egg should be of it as well."*
      So, precisely:
        * floor monsters are mostly the dungeon's own species, with a minority drawn from other
          species **of the same tier as the dungeon's grade** (which, after the grade change
          above, means the instance's grade, not the type's);
        * the BOSS stays the dungeon's own species, always;
        * the guaranteed clear EGG stays the dungeon's own species, always;
        * FLOOR eggs may come from any species that actually spawned in that dungeon - so the
          mixed pool feeds the egg pool, and a rarer species in the mix is a rarer egg.
      **DONE 2026-09-11.** `DungeonDatabase.pick_floor_species` decides each monster: 75% the
      dungeon's own, the rest neighbours from the same GRADE (the instance's grade, so an A5
      Goblin Dungeon draws A-grade company). The entity carries its own species, so the fight, the
      variant roll and the map letter all follow the monster the player walked into rather than
      the dungeon. Every species that spawns is remembered on the instance, and `_floor_egg_species`
      draws floor eggs from that list - so a species that turned up rarely yields a rare egg by
      the same token, and a species with no egg falls back rather than dropping nothing.
      The boss and the guaranteed clear egg are untouched, and the probe checks that explicitly.
      **The mix share is one constant, `NATIVE_SPECIES_SHARE`; setting it to 1.0 turns the whole
      thing off cleanly.**
      Probe `dungeon_species_mix.gd`. **Worth reading the note in it:** the first version checked
      the SOURCE for the mix and passed happily when the branch was replaced with `if false:`.
      It measures 20,000 picks now, and disabling the mix fails it.
      Still open here: `monster_pool` on the type is still read by nothing but the Atlas, which
      now under-promises rather than over-promising.



- [ ] **RANK DOES NOT PAY OFF IN EGGS, which is the reason to climb it. Owner 2026-09-11:**
      *"each of those higher ranked ones should ideally have a higher chance to drop higher rank
      eggs (we should check this and fix it if they don't)."* **Checked. Mostly they do not.**

      A dungeon has three egg sources and only ONE of them knows the dungeon's rank:
      | source | how many | does it inherit the dungeon's rank? |
      |---|---|---|
      | the boss egg, on completion | one, guaranteed | **yes** |
      | floor loot eggs, ~35% a floor | the volume | **no - it rolls `1 + randi() % 8`** |
      | treasure chests | - | yes, but the path is DEAD (see below) |

      So an H1 and an H9 hand out the same floor eggs: rank uniform 1-8, mean 4.5, in both. The
      only difference a player can feel is the single boss egg.

      **What rank is worth when it does land.** Egg rank becomes the companion's `sub_tier`, which
      multiplies its stats (1.0x at rank 1, 2.0x at rank 9) and its abilities (1.0x to 1.75x), and
      its valor (200 to 440 for a tier-1 egg). That is a big prize attached to one egg per run.

      **Four faults found while checking, all small and all in the same place:**
        1. `_roll_floor_item` TAKES `sub_tier` and never reads it - a dead parameter passed by
           three call sites. The egg line overwrites it with a random roll.
        2. The floor-egg roll is `1 + randi() % 8`, so a floor egg can **never be rank 9** even
           though dungeons now generate rank 9.
        3. A rank-9 dungeon already hands out a rank-9 BOSS egg, which is the 2.0x/1.75x tier the
           tables still label "Fusion-only (Phase 4)". Raising dungeons from 8 ranks to 9 appears
           to have opened that door by accident - it makes an H9 boss egg beat anything fusion
           can make below rank 9. **Wants a decision, not just a fix.**
        4. The rank-aware chest-egg path (`_open_dungeon_treasure`) is unreachable in player
           instances: `_spawn_all_dungeon_floor_items` blanks every treasure tile and re-homes it
           as floor loot, so the chest code never runs.
      Also: the FINAL chest rolls gear at the player's level, not the dungeon's, so its equipment
      is identical at rank 1 and rank 9. Materials and XP do scale with rank (x1.0 to x1.8); valor
      coins, boss materials, the card reward and escape scrolls do not scale with rank at all.

      **PARTLY FIXED 2026-09-11 - floor eggs now follow the dungeon.** `_floor_egg_rank` rolls in
      a window around the dungeon's own rank (two below, one above, named as
      `FLOOR_EGG_RANK_SPREAD_DOWN/UP` so the owner can widen or close it). Mean egg rank goes
      from a flat 4.5 at every rank to 1.5 at rank 1 and 8.0 at rank 9, rank 9 is reachable for
      the first time, and a given dungeon still gives several different ranks.
      **This is a real economy change in both directions:** low-rank dungeons got noticeably
      worse for eggs and high-rank ones noticeably better. That is the point, but it wants a feel
      check in play. Probe `floor_egg_rank.gd`; restoring the old roll fails it.
      **Still open from this item:** faults 3 and 4 (rank-9 boss eggs handing out the
      "Fusion-only" multipliers, and the dead chest path), the final chest rolling gear at the
      player's level rather than the dungeon's, and valor/boss materials/cards not scaling with
      rank at all.

- [ ] **A DUNGEON'S LEVEL AND THE LAND AROUND IT ARE UNRELATED. Owner report 2026-09-11, and it
      is exactly as reported.** Owner: *"I just did a G2 Kelpie Marsh at -23, -64 where the
      monsters are Lv ~16 on the overworld. Do dungeons spawn in similar level to the overworld
      area you find them? Ideally they should."* **They do not, and nothing in the code tries to.**

      **Traced, with the numbers for that exact tile.**
      | at (-23, -64), distance 68 from origin | level |
      |---|---|
      | overworld encounters | **15-17** |
      | the G2 dungeon standing on it | **7-9**, rising to ~12 on its deepest floor |

      **Why.** They are two ladders that never meet.
        * The OVERWORLD level is a curve on distance from origin (`_distance_to_level`), pulled
          DOWN near posts whose own origin-distance is lower, then multiplied by a hotspot roll.
          At distance 68 that lands on 16-17.
        * A DUNGEON's level comes from its TYPE's hardcoded tier, the rank that distance picks
          inside that tier, the floor index, and the player's level clamped into the rank's band.
          Tier 2's band is L6-22 and rank 2 of 9 is L7-9. **The overworld level at the tile is
          never read.**
        * And the TYPE is chosen **uniformly at random from every dungeon type** when a world
          dungeon spawns. `spawn_weight` exists in the data and is read by nothing.
      The only place the two systems touch is threat spill: monsters that leak out of a dungeon
      onto the map are clamped INTO the local band, so beside this dungeon you meet its Orcs at
      L15-17 while the same Orcs inside it are L7-9.

      **The mismatch is every tier, both directions, and the top end is enormous.** A dungeon's
      spawn ring is `tier*30 .. tier*60`, which has nothing to do with where the land reaches
      that dungeon's levels:

      | tier | spawns at | land there | its monsters | where the land would match |
      |---|---|---|---|---|
      | G1 | 30-60 | L4-14 | L1-12 | 0-55 |
      | G2 | 60-120 | L14-38 | L6-22 | 40-80 |
      | G3 | 90-180 | L26-68 | L16-40 | 65-125 |
      | G4 | 120-240 | L38-104 | L31-60 | 102-166 |
      | G5 | 150-300 | L50-140 | L51-120 | 151-266 |
      | G6 | 180-360 | L68-176 | L101-500 | 235-700 |
      | G7 | 210-420 | L86-220 | L501-2000 | 701-1320 |
      | G8 | 240-480 | L104-280 | L2001-5000 | 1320-1971 |
      | G9 | 270-540 | L122-340 | L5001-10000 | 1971-2828 |

      Tiers 1-5 sit BELOW their land; tiers 6-9 sit wildly above it. An S-rank dungeon holding
      L5001-10000 monsters stands in wilderness running L122-340.

      **And it exposes a second thing nobody had noticed.** Because every tier's ring is
      `tier*60` or less, **all 150-200 world dungeons live inside a radius of 540** - 5.7% of the
      world by area. The outer 94% of the map has no dungeons in it at all. The right-hand column
      above is also the fix for that: place a dungeon where the land matches its levels and the
      set spreads from the origin to the rim.

      **Correction to an earlier note here: this cannot be done as a pure filter.** "Only spawn
      types whose band fits the local level" sounds like the smallest change, but for tiers 6-9
      there is NO point in their current ring where the land fits, so a strict filter would stop
      them spawning entirely. The choice is really:
        * **(a) MOVE the dungeons** - replace `get_spawn_location_for_tier`'s `tier*30..tier*60`
          with the radius at which the land reaches that dungeon's own band (the last column).
          No level formula changes, no grade changes meaning, `power_rank.gd` stays the authority
          for both ladders, and the empty outer world fills in. Cost: high-tier dungeons become
          genuinely remote, which is a real change to how the endgame is reached.
        * **(b) RE-ANCHOR the levels** - the grade stays a flavour label and a dungeon's monsters
          take the overworld level at its tile. Every dungeon anywhere is enterable at local
          level. Cost: "G2" stops predicting difficulty, and the dungeon half of
          `TIER_LEVEL_BANDS` stops describing anything.
        * **(c) BOTH ladders get re-drawn** - accept that the distance curve and the tier rings
          are two descriptions of the same thing and derive one from the other. Cleanest, biggest.
      **OWNER DECIDED 2026-09-11: (a), MOVE THE DUNGEONS** - place each one at the radius where
      the land already reaches its own band. No level formula changes, no grade changes meaning.
      Measurable: spawn 500 dungeons, compare each one's band against `get_post_anchored_level`
      at its tile, and require the overlap.

      **And DENSITY: about one dungeon per 100 tiles walked, everywhere.** `tools/dungeon_density.gd`
      prices that at roughly **3,150 dungeons** against a live cap of 200. That number is only
      affordable after the world-dungeon interior work below - see the item on it - because today
      each one costs ~600 ms to spawn, ~620 KB to hold, and three linear scans per player move.
      **Do the cost work FIRST.** Raising the cap on the current implementation just moves the
      spike somewhere else.

      **Owner, same breath:** *"We will also want to make sure the entrances are hoverable and
      sprited once we get all of the overworld spriting in."* Recorded in Phase 2.95 PHASE 2 -
      a dungeon entrance is an overworld tile, so it sprites with everything else, and hover is
      the same surface as the three tooltip faults in Phase 3.

- [x] **SHIPPED v0.9.760-767 — the dungeon RENDERER, its sprites, and the hoverable key.**
      This replaces three separate open entries (~245 lines) that were still describing this as
      the next thing to build. Reconciled 2026-09-10 after the owner asked what the most efficient
      way to proceed was: a plan built on a list that calls finished work "NEXT" is wrong before
      it starts.
      What landed: the tile renderer on the main canvas, floor/wall-rim/void, landmark art
      (chests, lava, braziers, campfires, stairs), scatter props, animated monster sprites for all
      53, floor-loot and egg art, the player's own overworld sprite underground with a trailing
      companion, the run log and legend in the side panel, hover on a theme tile in the KEY and on
      the FLOOR, monster hover with pre-rolled variant, level and art, and prop occlusion.
      **The deleted geometry section was WORSE than stale — it was wrong.** It specified
      `DUNGEON_TILE_FONT_SIZE 46 -> 58` with `line_separation = -47`, an approach that was tried
      and abandoned: a negative separation does not merely tighten rows, it COMPRESSES the inline
      images, so tiles drew full width and half height while every headless measurement said 32px.
      Font 14 with no separation override is what actually works. Anyone planning from that entry
      would have rebuilt a known-broken design, which is exactly the cost of a stale backlog.
      **The live reference is the code, not this file:** `client/dungeon_tiles.gd` carries the
      sheet coordinates, `FLOOR_COLOR`, the tile-size rules and the reasoning for each; and
      `client/dungeon_sprites.gd` the glyph/monster/landmark tables. `tools/verify_dungeon_art.gd`
      calls every resolver on every key it claims to serve (840 lookups) and the release gate
      fails on any that does not load.
      **Two facts from that section worth keeping:** WALL is still deliberately drawn as void with
      the rock autotile used only as the RIM where floor meets void (owner's Azure-Dreams call);
      and `client/sprites/tilemap_pack/` is now LICENCE-RESTRICTED and untracked, so see
      `docs/ASSET_LICENCES.md` before touching it.
      Still open from the original scope, and now the only part that is: **the ~46 remaining THEME
      tiles are still coloured letters.** Landmark tiles got real art; flavour tiles (mud, moss,
      webbing, miasma) did not. They read acceptably and now carry scatter props behind them, so
      this is a polish item rather than a gap — and it is the natural companion to the Raven room
      work, which will settle what a themed floor should look like anyway.

- [ ] **Zoom the map inside NPC posts** (owner 2026-09-08) — **now part of Phase 2.95 PHASE 2, do
      not plan it twice.** *"We may also want to zoom in the map when players are in a post for
      the same type of functionality in the future."* Re-pointed 2026-09-11: this used to say
      Phase 3.45 (sprite interiors), on the belief that a post interior was its own screen. It is
      not - a post is tiles in the WORLD grid - so both the zoom and the post's sprites belong to
      the overworld renderer, and neither can happen before Phase 1 moves that renderer to the
      client. (The Dungeon Atlas was once tracked as three separate tasks in three places — that
      is the mistake this cross-reference exists to avoid.)

- [ ] **Dungeon revamp — the design IS captured**, in `docs/design/dungeon_revamp.md` (139 lines)
      plus `docs/design/dungeon_themes.md`. This line used to say "details not yet captured",
      which was stale and undersold how much has already shipped: instancing + no re-farm,
      bigger dungeons, wandering-monster pressure replacing the step budget, branching paths,
      four special room types, Azure-Dreams floor loot, and dungeons as the main egg source.
      Six workstreams; what is LEFT, and what each waits on:
        * **D bosses** (phases / telegraphs / adds, telegraph counterplay mandatory) — nothing
          blocks it.
        * **E presentation** (zoom, sprites, void instead of wall tiles, wider room spacing)
          — **DONE, shipped v0.9.760-767.** See the ticked entry above.
        * **A 2-4** (theme roll/stamp/display, themed egg, Sigil consumable) — nothing blocks it.
        * **B loot/discovery** (signature drops, Dungeon Atlas) — waits on the dungeon card pass,
          and the Atlas has grown into the realm meta-loop (Phase 6).
        * **F party in dungeons** (the declared north star, most architectural) — waits on the
          party system itself, which has unfixed bugs (Phase 4).
      **Balance rule REVISED 2026-09-08:** dungeons may be PARTY-UPGRADABLE — much harder, much
      riskier, much better rewards — provided a solo option always exists and is completable.
      Not "one dungeon, more bodies"; an opt-in difficulty tier, signposted before entry.
- [ ] **Dungeon-themed floor equipment** (owner 2026-09-08): *"higher chances for players to find
      floor equipment with affixes related to our matching the dungeon type. Example Balrog
      equipment in a Balrog dungeon."*
      The gap is small and precise, because **the pattern already exists one branch above it**:
      `server.gd::_roll_floor_item` receives `dungeon_type` AND `boss_egg_monster`, and the EGG
      branch uses them (floor eggs already match the dungeon type + tier). The equipment branch
      (`roll < 82`) calls `drop_tables.roll_dungeon_chest_equipment(tier, lvl)`, which takes only
      tier and level — so the dungeon's identity is in scope and thrown away.
      There is also a naming/affix pattern to copy rather than invent: `generate_arcane_hoarder_gear`
      / `generate_warrior_hoarder_gear` / `generate_trickster_gear` in `drop_tables.gd` already
      produce monster-flavoured items ("Arcane Hoarder's Ring of the Archon") with a level boost
      and their own affix roll. A Balrog's Depths run wants "Balrog's ..." on the same shape.
      Open questions to settle when this is picked up, NOT assumed now:
        * Does the theme drive a real AFFIX BIAS (fire/burn weighting in a lava dungeon) or only
          the name + a level/rarity boost? The owner said "affixes related to", so probably both.
        * How much higher is "higher chance"? Pick it against the drop-rate work, not by feel.
        * **Read `docs/design/equipment_reference.md` first** — the chase pool is epic+ only, and
          an item's class stats come from its BASE TYPE, not its affixes. Do not design a themed
          affix that no acquisition path can actually roll.
- [ ] **Dungeon Atlas** as hub + quest board.
- [ ] **Dungeon-centred questing** to replace the disliked overworld quests: clear / rescue /
      boss-hunt / gather.
- [ ] **Presentation pass — mostly SHIPPED, one piece left.** The map, minimap and in-dungeon
      GUI all landed across v0.9.760-767. What remains is narrow: **real in-game dungeon
      screenshots for the website**, which now show something worth showing.

## Phase 6 — realm meta and sinks

- [ ] **Real sinks for excess eggs and companions**: shops, breeders, trainers, fusers, companion
      tasks. Much is already scaffolded (fusion, breeder NPCs, egg market, kennel).
- [ ] **Living world / rework the posts.**
- [ ] **Launcher revamp + feedback inbox** — self-updating launcher, bigger window, changelog panel,
      and suggest-idea / report-issue buttons posting to a server inbox.

## Phase 7 — endgame: THE UNBURIED (deliberately later)

Owner 2026-09-07: not needed for a long while. It is the mechanism that makes the top of the ladder
reachable, so it pairs with revisiting the high-level win targets — but nothing depends on it yet.

An aspirational milestone admits a player to **The Unburied**: great powers that affect the realm
and other players, plus **3 extra lives**, and possibly a further life from a hard endgame loop
(deliberately not easy, so members are not effectively unkillable).

The name is exact against the setting bible: a phantom is a dead thing the ground refuses to keep
down, and these are the ones it keeps sending back — which is what extra lives ARE.

## Phase 8 — later / unscheduled

- [ ] **Prize Shuffle** loot-minigame redesign (combat done; gathering and crafting remain).
- [ ] **Crafting review** — owner: "not in a good spot at all."
- [ ] **Sanctuary redesign.**
- [ ] **Player phantoms.**
- [ ] **Minigame variety.**
- [x] **Card market smoke-tested 2026-09-10 — no faults found.** It had been "built, compile-clean,
      never exercised end to end", so this exercised it two ways.
      `tools/probe/card_market.gd` puts ALL 57 tradeable cards through the three lookups a
      listing is built from — display name, tier, valor — because a card that returns an empty
      name lists as a blank row and one that prices at 0 is given away, and BOTH succeed
      silently. All 57 pass; valor spans 220-2457.
      `tools/probe/card_market_roundtrip.gd` runs list -> merge -> price -> remove. The merge is
      the part worth having a test for: cards carry `supply_category: "card"`, which is NOT in
      the unique list, so a second listing of the same card by the same seller MERGES and sums
      BOTH quantity and base_valor. That is safe only because the buy side divides by quantity
      for a per-unit rate — proven here rather than assumed, since pricing a merged stack from
      `base_valor` directly would have charged double for one card.
      **Still unexercised**: the live wire path (`market_list_card` -> SQLite -> another player's
      `market_buy`) needs two connected clients; only the logic beneath it is covered.

---

## Hard constraints — do not relearn these

- **A deck is 5 cards + the companion loaner.** Cards past that only make the ones you want come up
  less often. **Duplicates do not work** — the seeding loop assigns `collection[name] = 1`.
- **Exclusivity is the tuning lever.** A card only one class starts with can be tuned freely; a
  shared card cannot be tuned for one class without moving the others. That is why Killing Edge
  could fix the Ninja and its deck could not.
- **Never state what GEAR can do from memory.** Read `docs/design/equipment_reference.md` or run
  `-- gearsources`.
- **Judge at +/-10pp, not +/-5pp.** At n=60 a win rate carries ~4.5pp of sampling error.
- **Archive with discussion.** Removing game elements is fine, but discuss first; improving beats
  removing.
