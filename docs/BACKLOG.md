# Phantom Badlands — Master Backlog

**The single ordered to-do list.** Read it before proposing what to work on; update it as work
lands. Items are ordered so each one's inputs are settled before it starts — working out of order
is what forces revisits.

History lives in `docs/archive/BACKLOG_journal_to_2026-09-07.md`. Search it before re-opening
anything: it records why several approaches were REJECTED, and re-proposing those is the most
common way to lose a session.

---

## Where the game is (2026-09-09)

Live: **v0.9.763** (client + server), released 2026-09-09.

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

## Phase 1 — confirm the two releases landed (do first, cheap)

- [x] **Shutdown handler fired every frame until the process exited — FIXED 2026-09-09.**
      `_execute_pending_shutdown` awaits a second (so the goodbye broadcast lands before sockets
      close), and `_process` keeps running across an await with `pending_update_active` still true
      and the counter at zero — so it re-entered every frame. 60fps x 1s = the 61 copies seen in
      the v0.9.763 deploy log, meaning any connected player was told the server was shutting down
      sixty times. Latched inside the function rather than at the call site, since the re-entrancy
      is a property of the function being async. Verified on production by springing a real
      countdown: **1** shutdown line and **1** broadcast, down from 61.

- [ ] **Confirm the dungeon tile HOVER on screen** (owner 2026-09-09, working remote: *"it will
      need confirmed later once I'm back at my PC"*). Everything a screenshot can show was
      checked — the `[url=]` is emitted, the key entry renders underlined as a live link, the
      handler is connected on `map_display` as well as `game_output`, and the popup parents to
      the window root so it shows outside combat. What was NOT verified is the rendered tooltip
      itself, because it needs a real mouse hover. Check a theme tile in the key AND one on the
      floor; the text should wrap rather than run off screen.

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

## Phase 3 — combat UX debt (visible to every player, every fight)

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

## Phase 4 — party (half-built; finish or cut)

- [ ] **Invite window** and **watch-a-teammate's-minigame** — the two remaining Party UI pieces.
- [ ] **Party fairness**: verify every member really receives combat rewards (especially equipment),
      rotate the leader between fights, consider splitting gathering/crafting/loot rewards.
- [ ] **"Party play isn't working properly"** (owner, 2026-08-26) — no repro captured. ASK for the
      symptom before investigating.
- [ ] **Leader logout must not strand the party.**

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

- [ ] **NEXT: dungeon tile renderer** — art is IN, geometry is MEASURED, nothing is blocking it.
      Owner chose `darkcave` over Godot Pixel Levels on look. Committed at
      `client/sprites/darkcave/` (2 sheets), `mobs_pack/` (366 animation strips),
      `items_pack/` (~1500 by equipment slot).

      **Geometry, measured not assumed** (a monospace canvas can host a square tile grid):
        - `DUNGEON_TILE_FONT_SIZE` 46 -> **58**: Consolas cell becomes exactly **32px** wide, a
          perfect **2x integer scale** of a 16px tile and **1:1** for the 32px wall sheet.
          Non-integer scaling is what makes pixel art mushy, so this number is the whole point.
        - `line_separation` **-47** on `game_output` while the dungeon draws: rows land at
          exactly 32px, giving square cells. Measured: -45 -> 34px, -47 -> 32px, -50 -> 29px.
        - NEAREST filtering: DONE (was missing; the player avatar was being drawn soft).
        - Cost: a full 25x11 floor of inline `[img]` measured **16.67ms vs 15.70ms** for text
          glyphs - 1.1x. No renderer rewrite needed.

      **Sheet contents, indexed cell by cell rather than guessed:**
        - `dark cave_tiles_and_sprite_16x16.png` (22x12): olive FLOOR autotile at cols 5-11 rows
          1-5; the same shapes in BLACK at rows 7-11 (pit/chasm); props at cols 13-20 - grass,
          pebbles, moss, **gold nuggets**, skull, dead branch, sapling, **campfire (2 frames,
          animated)**, bookshelf, **2 lanterns**, and a 3x3 **tent**.
        - `dark cave_wall_32x32.png` (12x6): a classic **4x4 autotile block at cols 1-4 rows
          1-4**, rocky edges with a BLACK interior; cols 5-11 are decorated variants.

      **Key design point:** WALL is deliberately drawn as blank void today (owner: "render
      non-traversable space as empty/void... Azure Dreams style"), so do NOT carpet the map in
      wall sprites. Use the wall autotile only as the RIM where floor meets void - its black
      interior means the deep void stays black and rooms read as carved out of rock. This uses
      the art for the shape it actually has and keeps the existing design.

      **Natural mappings already available:** campfire -> rest site, tent -> safe room, gold
      nuggets -> resource node (`&`), `mobs_pack/ChestA` (a mimic) -> treasure chest, skull ->
      remains.

      **Stairs and doors are SOLVED** (owner supplied `RageTileMap-master`, 2026-09-08). Its art
      is the Henry Software Pixel Level set - the SAME artist as mobs_pack/items_pack, so it
      matches them by construction. Curated to `client/sprites/tilemap_pack/`:
        - `free_tiles_16x16.png` (32x4) and `paper_tiles_16x16.png` (48x64, ~3000 tiles)
        - the two C# tile ENUMS kept as `*.cs.reference` - they NAME every index, so no tile has
          to be identified by eye. Index -> cell is `(i % across, i / across)`; across = 32 for
          free, 64 for paper.
      Verified by rendering each index and looking at it, not by trusting the enum:
      `12 StairsDown, 13 StairsUp, 14 DoorShut, 15 DoorOpen, 16 DoorBroke, 17-20 WallTorch
      (a 4-frame animation), 21-28 Wall, 38 Bed, 39 Sacks, 47 Forge, 48 Anvil, 49 Workbench`.
      `47 Forge` is worth noting - the game already has an Infernal Forge.

      **Tile size / view count may want revisiting** (owner 2026-09-08): *"We may have to find a
      size and number that works for the future if it starts looking that bad. Currently this
      looks great."* Now 64px tiles at a 19x9 view. Revisit if props, monsters and loot make the
      floor feel cramped.

      **Solid darkcave tiles, found by scanning for a fully-opaque uniform cell rather than by
      eye:** floor = **(2,2)** `#524B24` (zero colour spread), void = **(2,8)** black. A first
      mock used (6,2) and produced a room covered in black notches - that is an EDGE tile. The
      autotile cells must be identified the same measured way.

      A mixed mock (darkcave floor + wall rim, RageTileMap stairs/doors/torch/forge) reads fine:
      the warm brown stone sits comfortably against the cave rock.

      - [x] **DONE, VERIFIED ON SCREEN 2026-09-09 - Scatter FLAVOUR props on the floor** (owner 2026-09-08, on seeing slice 1): *"We
            will likely want to add some of the stones, grass, trees, stumps, lanterns scattered
            around in the future just for flavor to make the floor less of the same thing."*
            The olive floor reads correctly as cave floor - confirmed by the owner - but every
            tile is identical. The cave sheet already carries the props: grass tufts and pebbles
            (cols 13-14, rows 2-4), moss, a skull (19,2), a dead branch (17,3), a sapling (19,3),
            and lanterns (19-20, rows 5-6); `tilemap_pack` adds dead trees and stumps.
            Do it as a DECORATION layer keyed off the tile position (a hash of x,y so it is
            stable across redraws and does not shimmer as you walk), at a low density - flavour,
            not clutter, and never on a tile whose meaning a player must read.

      - [x] **DONE, VERIFIED ON SCREEN 2026-09-09 - Companion follows you underground** (owner 2026-09-08): *"We will eventually want
            the companion following your sprite in dungeons just like on the overworld as well."*
            The overworld already does this with `_local_companion_label` / `_make_map_companion_label`
            (a small monospace RichTextLabel of the companion's ASCII art, positioned under the
            player's map sprite). The dungeon cannot reuse that directly: the overworld map is an
            OVERLAY of positioned Controls, while the dungeon grid is inline text, so the
            companion has to be a tile in the grid, drawn one cell behind the player.
            Two pieces are missing and worth checking before starting: the companion has no
            POSITION in a dungeon (nothing server-side tracks one), and it would need a trailing
            rule - remember the player's previous cell and draw the companion there, which also
            gives it a facing for free. Sprite source: the companion art already used on the
            overworld, or a `mobs_pack` match once monsters are sprited.
            **Verified 2026-09-09, and it took an instrument fix to do it.** Two things hid it:
            the test save's companion was KO'd (a downed companion is not drawn), and the
            `dungeon` capture scene sent the OVERWORLD `move` message instead of `dungeon_move`,
            so the player never took a step - 450 redraws at one cell, and the companion stands
            on the player's PREVIOUS cell, which never existed. Both shots looked entirely normal.
            `_dev_shot_ensure_companion` now revives as well as grants, and the scene moves with
            `dungeon_move`. The wolf then appears behind the player exactly as designed.

      - [x] **DONE - monster sprites (loose matches, owner's call).** All 82
            `mobs_pack` families were rendered and compared against the 53-monster roster
            (2026-09-08). About 35 map WELL: undead (Skeleton/Zombie/Skull/Ghast), Mimic->Chest,
            Vampire->Count, Death Incarnate->Reaper, Wolf/Gnoll/Cerberus->Dog, Hydra->Snake,
            Elemental->ElementalOrb, Iron Golem/Titan->Golem, Shrieker->Mushroom, God Slayer->
            Sword, Void Walker->Space, Balrog/Phoenix->FireSmall.
            The pack is slimes, skulls, orbs, elementals, bugs, animals and constructs - the only
            humanoid-ish families are Count, Mummy, Zombie, Witch, Reaper, Robot, Dwarf, Beard,
            Skeleton, Golem, Head. Our roster is heavy on classic humanoids (Goblin, Kobold,
            Hobgoblin, Orc, Ogre, Troll, Giant, Gnoll) and NONE of them match; a first pass put
            four of them in `Hulk`, which is a many-armed insect. Also weak: Gargoyle->Monolith
            (a brown slab), Sphinx->Mask, Cosmic Horror->Eye (renders nearly empty).
            Owner to choose: (1) sprite only what fits and keep glyphs for the humanoids - never
            shows a wrong-looking monster, degrades cleanly as art arrives; (2) accept loose
            matches so everything is a sprite; (3) source a humanoid pack.
            Sprites are 16x16 frames in horizontal STRIPS (SkeletonA = 144x16 = 9 frames), so
            frame 0 is a region and animation is available later at no extra cost.

      - [ ] **Animated STATUS-EFFECT art for combat** (owner 2026-09-08, pointing at
            `tf_svbattle/RMMV/system`). `States.png` is 768x960 - **10 status animations of 8
            frames each** in 96x96 cells, and the pack's own readme calls them "a set of
            animations for status effects (poison, sleep, etc)... pixel-art animation in the
            style of Time Fantasy so there won't be a style clash".
            Rendered and identified: 1 poison (purple bubbles), 2 blind (eye + red X), 3 silence
            (speech bubble), 4 stun/armour-break (closing brackets), 5 confusion (question
            marks), 6 charm (hearts), 7 sleep (Zzz), 8 paralysis (lightning), 9 doom (skulls),
            10 freeze/slow (blue drops).
            Combat currently shows statuses as TEXT chips with `[url=]` hovers. These would sit
            on the combatant instead - and note they are ANIMATED, which the text chips are not.
            `Shadow2.png` in the same folder is a deliberate BLANK: the Time Fantasy style bakes
            the shadow into each sprite, so it overwrites the engine's default drop shadow. Do
            not mistake it for missing art.

      - [x] **DONE - all 80 characters have directional art** (owner bought TF Sprites 2): `tf/6_1..6_8` and `tf/7_1..7_8`
            (paths `client/sprites/battlers/tf/<id>/idle_0.png`). Coverage is 64 of 80 after
            wiring chara1 -> row 1 and military1-3 -> m1-m3. The only unused CHARACTER sheets left
            are `fairies` (4 winged), `vampire` (a vampire and a bat) and `bonus1` (8 in modern
            dress) - none are the armoured adventurers in rows 6/7, shown side by side rather
            than asserted; `npc*` are plainly townsfolk in aprons and overalls.
            **Why they are missing is now known.** The battler pack's readme: "This is an
            EXPANSION pack for the Time Fantasy RPG assets... expands on the characters from
            PREVIOUS Time Fantasy sets", and `singleframes/` holds exactly set1-set7 +
            military1-3 = 80, matching `tf/` one for one. So all 80 battlers DO have character
            counterparts - across the wider Time Fantasy product line, not inside the single
            character pack we own.
            **The missing set is IDENTIFIED.** The battler pack's page: "80 characters based on
            the heroes from the original Time Fantasy set and the Monsters expansion", plus "For
            base walking animations for these characters, check out the original character pack".
            Our `READ_ME.txt` confirms we own the ORIGINAL - "32 main hero/villain characters, 24
            military characters, 16 NPCs (recolored -> 32), 8 bonus characters" - which is
            exactly rows 1-5 and m1-m3, and explains why `npc`/`bonus` never matched: they are
            townsfolk, not battler heroes.
            So rows 6-7 need **Time Fantasy RPG Sprites 2 (with Monsters)**,
            <https://finalbossblues.itch.io/time-fantasy-monsters>, **$10 minimum**, which ships
            "all monsters with full four-direction walking animations and single-frame battlers".
            Four-direction walking is precisely the missing art. Same artist and style, so it
            drops in beside what is already wired.
            Until then they keep the mirrored-battler fallback (left/right facing, no walk cycle).

      - [ ] **Player EMOTE animations underground** (owner 2026-09-08): the walk cycle IS live -
            each step advances a 3-frame cycle from the overworld art's 4 directions x 3 frames -
            but the EMOTE sheets are a separate thing and are NOT done. They sit unsliced at
            `timefantasy_characters/sheets/emote2..5.png` (312x288 = a 12x8 grid of 26x36 frames)
            plus `animation1/2.png`, and larger 936x864 copies under `RPGMAKERMV/characters/`.
            The pack's `frames/` folder slices chara/military/npc/animals/chests but never the
            emotes, so they need a slicing pass first - the same offline treatment the avatar
            frames got. Then decide WHEN one plays: on rest, on a find, on low HP.

      - [ ] **Dungeons must support PARTY play** (owner 2026-09-08: "we will also need to ensure
            Dungeons support party play at some point"). Already the declared north star under
            phase F below and carries the revised balance rule (party-upgradable dungeons: much
            harder, much greater rewards, but always with a solo option). Recorded HERE too
            because the tile renderer now makes a concrete demand of it that did not exist
            before: the grid draws exactly one player sprite and one trailing companion, so a
            party needs other members drawn as their own sprites in the same grid, each with
            their own facing - and the client currently has no positions for them underground.
            Same shape as the companion follower, one step harder.

      - [x] **PARTLY DONE - landmark tiles sprited; doors/traps/trees still unused** (owner 2026-09-08: "there are some trees and
            traps and things that could be useful"). All under
            `client/sprites/battlers/timefantasy_characters/timefantasy_characters/RPGMAKERMV/`:
              `characters/!doors.png`       576x768  - DOORS: wood, red, metal, barred variants
              `expansion/switch1.png`       576x768  - pressure plates, levers, buttons, gems:
                                                       trap and switch art
              `expansion/bonus_lava_anim.png` 432x144 - ANIMATED lava, i.e. the LAVA_POOL theme
                                                       tile exactly
              `characters/!$torch.png`      144x240  - animated torch, several variants
              `characters/!$fireplace.png`  144x240  - animated fire
              `expansion/bonus_trees.png`   480x576  - 12 trees
              `expansion/bonus_pinktrees.png` 576x192 - 2 cherry trees
              `expansion/bonus_kitchen.png` 192x288  - counters and tables
            This closes gaps I had twice reported as missing. Note the theme-tile matches are
            direct: LAVA_POOL -> lava, and the trap glyph -> a pressure plate. Torch and fire are
            ANIMATED, which suits a lit corridor or a rest site.
            Slice them the same way row 1 was: RPG Maker sheets are 12 cols x 8 rows of frames,
            character blocks are 3 cols x 4 rows, and `!`-prefixed files are OBJECT sheets rather
            than characters (different layout - check before assuming the block maths).

      Slice it: (1) floor + wall-rim + geometry, screenshot, iterate. (2) props and the special
      tiles. (3) monsters from `mobs_pack` with the hover already built. (4) floor loot from
      `items_pack`. (5) the hoverable key, using the `[url=]` idiom.

- [ ] **Dungeon sprites, and a hoverable key** (owner 2026-09-08):
      ⚠ **CORRECTION 2026-09-08 — the "~4,900 sprites available" note below is misleading.**
      Both packs carry a **0-byte `.gdignore`**, so Godot imports NOTHING from them: they are not
      in the .pck (checked `.godot/imported` — zero entries), so they are not inflating the
      download either. Using any of them means selectively un-ignoring, which is the lever for
      taking a few without pulling in all 4,900.
      **And they are almost entirely CHARACTER battlers.** A first sweep for tile/environment art
      wrongly concluded there was none, by searching path keywords (`*tile*`, `*object*`) instead
      of reading the packs — the "wrong unit" mistake CLAUDE.md warns about. What actually exists
      for non-character art is narrow but real:
        - `timefantasy_characters/frames/chests/` — **32 frames**, 8 chests x 4 states
        - `timefantasy_characters/frames/animals/` — **96 frames**, cats + dogs
        - `timefantasy_characters/sheets/` — unsliced sources incl. `chests.png`, `animals1.png`
      There is **no floor / wall / door / stairs / trap art anywhere in the repo**. So loot chests
      and some creatures can be sprited from stock; the TILES cannot, and need either sourced art
      or a proper typographic pass. Owner has not yet chosen between those. ASK before starting. *"ideally we will use sprites
      or something for these spaces as well as floor loot and such. We want to use sprites as much
      as possible for the dungeons. We will want to ensure they are added to the key on the right
      as well though. It could be hoverable like our other hover features to see what it actually
      does."*
      Prompted by the `g` glyphs on a Minotaur's Labyrinth floor. **Note the collision this
      exposes:** theme tiles are drawn as LETTERS while the key says "Letters = Monsters", so a
      bull-rune tile and a goblin look the same. Sprites fix that by removing letters from
      non-monster things entirely.
      Scope: theme tiles, floor loot (currently ◉ egg / ◆ gear / ♦ consumable / ▪ material /
      ¢ valor / ! scroll), special rooms, traps, stairs. Sprite candidates were already scouted
      — unused single-frames under `client/sprites/battlers/tf_svbattle/singleframes/` and
      `timefantasy_characters/`; the load pattern to copy is `battler_sprite.gd`.
      The KEY must list every sprite used, and each entry hovers to explain what the thing does —
      the same `[url=...]` + `meta_hover_started` → `_show_formula_popup` idiom the combat status
      chips and card damage numbers already use.
      **Do AFTER the room spread**, and after the zoom/font is settled: sprite size depends on how
      many tiles are on screen, and that is not final until a floor actually fills the view.
      **Unused art already in the repo** (verified 2026-09-08, not recalled): `tf_svbattle/`
      **3,042 PNGs** and `timefantasy_characters/` **1,829**, neither referenced anywhere in the
      client — the code only loads `sprites/ascii/`, `sprites/battlers/`, `battlers/overworld/`,
      `battlers/tf/` and `sprites/classes/`. So ~4,900 sprites are available without sourcing
      anything. ⚡ They also ship inside the .pck; check whether the unadopted packs are inflating
      the download and `.gdignore` what we do not use (dev screenshots once cost ~23MB an update
      the same way).
- [ ] **Zoom the map inside NPC posts, the way dungeons now do** (owner 2026-09-08): *"We may
      also want to zoom in the map when players are in a post for the same type of functionality
      in the future."* Same shape as the dungeon presentation pass: a post interior is a small
      bounded area drawn at overworld scale, so it wastes the canvas and its sprites are too small
      to read. The dungeon work already built the pieces — a large-font grid on the main canvas,
      a side panel for status/legend, and `_dungeon_player_glyph()` drawing the player's overworld
      sprite inline at the measured cell width. Deliberately AFTER the dungeon arc so the tile
      size, sprite sizing and key layout are settled once rather than twice.
- [ ] **Dungeon monsters: hover for art, level and type** (owner 2026-09-08): *"find a few sprites
      we can use for them or just make it where players can hover their mouse over them in the
      dungeon and see their ascii art (and optionally level and variant or type... Level 8 Venomous
      Orc)... this would require that the type of encounter get chosen beforehand I assume."*
      **Half of that assumption is already satisfied — checked, not guessed.** A dungeon monster
      entity is created with BOTH `monster_type` and `level` at spawn
      (`_spawn_dungeon_floor_monsters`), and `monster_type` is ALREADY sent to the client as
      `type` in the `dungeon_state` monster list. So "Level 8 Orc" + its ASCII art (client already
      has `monster_art.gd`) needs only ONE extra field on the wire: `level`.
      What is NOT pre-decided is the VARIANT (Venomous / elite / empowered) — that is rolled when
      combat starts. Pre-rolling it at spawn is a real design change, and arguably a good one
      under permadeath: seeing a Venomous Orc coming down the corridor is information you can act
      on. Decide that separately; the cheap 90% does not depend on it.

- [ ] **Dungeon revamp — the design IS captured**, in `docs/design/dungeon_revamp.md` (139 lines)
      plus `docs/design/dungeon_themes.md`. This line used to say "details not yet captured",
      which was stale and undersold how much has already shipped: instancing + no re-farm,
      bigger dungeons, wandering-monster pressure replacing the step budget, branching paths,
      four special room types, Azure-Dreams floor loot, and dungeons as the main egg source.
      Six workstreams; what is LEFT, and what each waits on:
        * **D bosses** (phases / telegraphs / adds, telegraph counterplay mandatory) — nothing
          blocks it.
        * **E presentation** (zoom, sprites, void instead of wall tiles, wider room spacing)
          — nothing blocks it. **IN PROGRESS 2026-09-08.**
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
- [ ] **Presentation pass**: map, minimap, GUI, and real in-game dungeon screenshots for the site.

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
- [ ] **Live smoke test of the card market** (built, compile-clean, never exercised end to end).

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
