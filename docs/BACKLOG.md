# Phantom Badlands — Master Backlog

**The single ordered to-do list.** Read it before proposing what to work on; update it as work
lands. Items are ordered so each one's inputs are settled before it starts — working out of order
is what forces revisits.

History lives in `docs/archive/BACKLOG_journal_to_2026-09-07.md`. Search it before re-opening
anything: it records why several approaches were REJECTED, and re-proposing those is the most
common way to lose a session.

---

## Where the game is (2026-09-09)

Live: **v0.9.766** (client only), released 2026-09-10. **UNSHIPPED in master: the
arrow-key diagonal movement** — held back deliberately, awaiting the owner's playtest of the 70ms
chord window. Do not let it ride along in the next release until that has happened.

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

## Phase 1 — confirm the two releases landed (do first, cheap)

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

- [ ] **The upgrade pool cannot make ANYTHING rare — measured 2026-09-10.** The owner's goal for
      this arc is *"wide enough that some players are telling their friends about ones they found
      that their friends have probably never seen."* That is a statement about RARITY, and the
      pool is currently incapable of it at any size.
      **Why.** `draw_choices` does `pool.shuffle()` and takes the first 9. Selection is uniform, and
      9 are shown at once. Measured against the real pool (51 upgrades, all wired):
      | card kind | eligible at m1 | seen after m1 | after m3 | after m5 |
      |---|---|---|---|---|
      | damage | 22 | **41%** | 79% | 93% |
      | buff | 19 | 47% | 86% | 96% |
      | control | 18 | 50% | 87% | 97% |
      A damage card shows **41% of everything it can ever be offered at its FIRST rank-up**, and
      after five milestones the chance a given upgrade has never appeared is 7%. Adding entries
      does not fix this: doubling the pool still shows 9 at once and still converges.
      **So the fix is a rarity WEIGHT, not more content.** Simulated: 16 common + 6 rare (weight 1
      against 10) leaves a player having seen 31% of the rare ones after five milestones; 30 + 12
      leaves 15%. That is the "you found THAT?" moment, and it costs one field per upgrade plus a
      weighted draw. Content widening still helps afterwards — CONTROL is thinnest at 18 — but
      weighting is what makes width mean anything.
      Do this BEFORE authoring more upgrades, or the new ones dissolve into the same uniform draw.

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

- [ ] ~~Write the BAKE GENERATORS as committed tools. The real fix behind the backup above.
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

- [ ] **Asset licences: two open items** (raised 2026-09-10 by the owner asking whether the Raven
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

- [ ] ~~Three attributes produce no comparison line of their own.~~ DEX, INT and WIS are read
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

- [ ] ~~36% of player actions report less damage than the monster loses.~~
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

**Measured first, and the answer inverts the worry.** All figures from
`tools/probe/overworld_sprite_cost.gd` and a standalone timing of `generate_map_display`.

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

- [ ] **PHASE 1 — move overworld rendering to the CLIENT. No art, no visual change.**
      Send tile DATA and let the client draw, exactly as the dungeon already does. Purely
      architectural, independently valuable, and measurable on its own:
      server render CPU -> ~0, wire 13,333 bytes -> ~529 bytes + entities (roughly 10-25x less).
      **Player capacity goes UP**, because this removes the most expensive per-player operation
      the server performs.
      Do this FIRST and alone. Coupling it with the art would make a performance regression and
      an art regression indistinguishable — the exact trap that hid the boss ring and the
      missing post-stamping.

- [ ] **PHASE 2 — sprite it, as a client-only concern.**
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

- [ ] **The cycled SHIELD absorbs nothing.** Owner: *"Cleave cycling says it gave 6 shield.
      Combat log says Kobold attack and deals 16 damage to which my healthbar is now missing 16.
      If the shield did something we should specify since it looks like it never existed."*
      Screenshot confirms it: `Cleave cycles — 6 shield.` then `The Kobold attacks and deals 16
      damage!`, HP 200 -> 184, and the damage HOVER lists only `Mitigation -10% taken
      (Constitution 10%)`. That hover is built by `_note_mitigation`, which
      `_damage_player_with_shield` calls whenever it absorbs — so the absorb did not run, i.e.
      `combat["forcefield_shield"]` was 0 at the moment the hit resolved.
      **Established.** `_cycle_unplayed` (combat_manager.gd:13656) adds to `forcefield_shield` on
      the LIVE `combat_state`, not a copy, and the player had missed, so the path was
      `_cycle_hand_after_attack`. Both write the real dict. The shield is therefore granted
      correctly and read correctly — which leaves ORDER.
      **The likely cause, not yet confirmed:** log order is not resolution order. Messages are
      appended to `msgs` arrays that are assembled for display, so the monster's attack probably
      resolves BEFORE the hand cycles, and the log simply prints them the other way round. If so
      the fix is the sequencing, not the shield.
      **Do not guess a third time** — this is a combat-ordering change and the round structure
      has to be read first. Confirm by logging the value of `forcefield_shield` immediately
      before the monster's damage is applied.

- [x] **SOLVED 2026-09-11 — same cause as the re-farm and the lingering "D".** Read off the
      live server log, not reasoned about: the owner re-entered a personal instance that had
      ALREADY been completed in an earlier session, so its saved grid still held the FINAL_CHEST
      and its saved monsters still held the boss marked dead. Completion is now recorded on the
      instance itself (`completed_at`), which the reload prune, the despawn sweep and the
      entrance lookup all already keyed off and were never told.

- [ ] ~~A dungeon completed with no boss in it. Owner: *"I just did a T1-1 Goblin Dungeon and
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

- [ ] ~~Make variant names and traits HOVERABLE. Owner 2026-09-10: *"We should also consider
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

- [ ] **Does the health bar lag on multi-hits / monster abilities?** Owner asked, and hedged:
      *"I may have been moving too fast though."* Two things ruled OUT: the bar's tween is 0.3s
      (`animate_hp_bar_change`), and the bar reads `character_data.current_hp` directly, so it is
      not a slow animation and not a stale field.
      What is NOT ruled out is message timing — combat playback is PACED (`_drain_combat_queue`)
      while `character_update` is not, so the bar and the log are driven by different clocks.
      Needs a measurement, not an opinion: log the arrival time of `character_update` against the
      queue drain for a multi-hit round.

- [~] **LIKELY SOLVED 2026-09-11, awaiting one confirmation.** Almost certainly the same cause as
      the bossless dungeon and the re-farm: the owner was re-entering a personal instance that had
      already been completed, which KEEPS its original sub-tier and skips the whole
      `if instance_id == "":` branch — and that branch is where the sub-tier inherit lives. So the
      tile advertised its own depth while the instance kept the one it was born with. Completion
      is now stamped on the instance, so a finished run can no longer be re-entered.
      The entry diagnostic is still in place; confirm on the next fresh dungeon and close it.

- [ ] ~~A dungeon still opens at a different depth than the tile advertised.~~ Owner: *"On the
      overworld this said it was a T1-2 Forgotten Crypt. I entered and it is a T1-7."* This is the
      SECOND report; the 2026-09-08 inherit was supposed to end it and reads correctly on the
      page. A diagnostic now logs, at entry, what the tile resolved to and what the instance got,
      flagging both failure shapes by name (shipped 2026-09-10, no behaviour change).
      **Next step is to read that log, not to theorise again.** The shape to expect is
      `tile=NONE`: `_get_dungeon_at_location` finding nothing at the player's feet even though
      the entrance panel had just printed a sub-tier from the same call, after which the depth
      falls back to a distance roll.
      Separately and definitely wrong, found while reading: the dungeon LIST
      (`server.gd` ~29136) matches an instance by dungeon_type ALONE — no location, owner or
      completed filter — so it reports the sub-tier of whichever instance of that type comes
      first in dictionary order, which may be a different dungeon entirely.

- [ ] **The kennel screen does not show a companion's sub-tier, and cannot inspect one.** Owner,
      in passing: *"it doesn't list its current subtier in that screen or let you inspect them"*.
      The data is already on the wire — `_build_companion_stable_payload` sends `sub_tier` per
      companion. This is a display gap, not a plumbing one.

- [ ] **Returning a checked-out companion — owner's call.** Owner: *"should we make a way for
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
- [ ] **PARTY has no un-submit, and that is where a confirmation step is actually needed.**
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

- [ ] **Answer the owner's own feasibility question first: does the OVERWORLD have to become
      sprites too?** It does not. A post interior, the sanctuary and a dungeon room are each a
      SEPARATE screen from the overworld map — `_render_house_map()` already draws the sanctuary
      as its own thing. The dungeon proved a monospace text canvas can be a sprite grid with no
      renderer rewrite, so an interior can be spritten without touching the overworld at all. The
      mixed look is a deliberate split (sprite interiors, ASCII wilderness), not a compromise.
- [ ] **The assets are ready and better than what we have.** Every Raven pack ships the SAME
      tileset pre-rendered at 16, 32, 48 and 64px, so a 64px cell draws at native resolution with
      zero scaling — sharper than the current dungeon floor, which is a 16px tile upscaled 4x.
      178 of 190 files sit on a clean 16 grid. `interiors` covers post interiors, `cozy_home` the
      sanctuary, `craft_stations` the forge and workbenches we already have, and
      `green_dungeon` / `miners_cave` / `the_underworld` the dungeon rooms. They also ship RPG
      Maker autotile sheets (`RF_*_A4` walls, `A5` floors, `B`/`C` objects), which is free
      information about which cells are floor and which are wall.
      One anomaly: `the_underworld` sheets are 654x366, NOT a multiple of 16 — it has padding the
      others do not. Check before using it as a grid.
- [ ] **Cost is not a reason to hesitate — measured 2026-09-10.** Client cost scales with CELLS ON
      SCREEN, not with how many tiles are owned: a room built from sprites costs the same as a
      corridor built from sprites. The SERVER has no idea sprites exist (not one `.png` reference
      in `server.gd` or `shared/`), so none of this touches concurrent player capacity. The two
      things that WOULD cost: a second draw layer per cell (doubles the inline images), and pck
      size — 6.6MB unzipped, negligible.
- [ ] **Slice it the way the dungeon was sliced**, which worked: one interior end-to-end
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

- [ ] **Pick the room pack by MEASUREMENT, not by name.** Palettes compared in HSV against the
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
- [ ] **Room VARIETY — DECIDED 2026-09-10: unique and fun beats coherent.** Owner, walking the
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

- [ ] **THREE LAYERS per room — the owner's design, 2026-09-10.** *"If for each room we were to
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

- [ ] ~~Floor loot should be HOVERABLE (owner, 2026-09-10): *"I wonder if it makes sense to make
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
- [ ] **The renderer needs no change; telling a room from a corridor is the actual work.** A room
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

- [ ] **DECIDED 2026-09-10: torch + lamps, and DARKNESS IS A DUNGEON TRAIT.** Owner, after
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
- [ ] **Cheaper atmosphere worth considering before any shader:** the compositor can already bake
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

- [x] **FIXED 2026-09-11.** The ramp is now ONE computation, `CombatManager.engine_damage_ramp`,
      called by the funnel for both classes and sent as combat state (`engine_damage_ramp`)
      exactly as `finisher_value` is. The client caches and multiplies by it; the probe asserts no
      copy of RANGER_AIM_DMG_PER or BARBARIAN_RAGE_DMG_PER exists in client CODE, so tuning
      either constant cannot desync the card face again. Display-only: no damage changed, no
      calibration run needed.

- [ ] ~~EVERY Ranger and Barbarian card understates its damage, by up to 88%.~~ Found 2026-09-10
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

- [ ] ~~A Ranger cannot crit with abilities, so every crit buff is dead weight for them.~~ Raised
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

- [ ] ~~Combat card hotkeys read R, 1, 2 instead of 1, 2, 3~~ (owner, 2026-09-06):
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

- [ ] ~~Ranger and Ninja STARTER decks~~ (owner, 2026-09-06): *"They should start with cards from
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

- [ ] **Accuracy audit: help screen, project docs, CLAUDE.md** (owner, 2026-09-07, partially done
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

- [ ] **Zoom the map inside NPC posts** (owner 2026-09-08) — **now part of Phase 3.45, do not
      plan it twice.** *"We may also want to zoom in the map when players are in a post for the
      same type of functionality in the future."* This and the sprite-interiors arc are the same
      screen: a post interior drawn larger, with sprites. Phase 3.45 owns the design; this line
      stays only so the older ask is not lost. (The Dungeon Atlas was once tracked as three
      separate tasks in three places — that is the mistake this cross-reference exists to avoid.)

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
