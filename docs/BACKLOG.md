# Phantom Badlands — Master Backlog

**The single ordered to-do list.** Read it before proposing what to work on; update it as work
lands. Items are ordered so each one's inputs are settled before it starts — working out of order
is what forces revisits.

History lives in `docs/archive/BACKLOG_journal_to_2026-09-07.md`. Search it before re-opening
anything: it records why several approaches were REJECTED, and re-proposing those is the most
common way to lose a session.

---

## Where the game is (2026-09-07)

Live: **v0.9.756** (client + server). Two releases shipped that day.

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

- [ ] **Watch the five live characters at L3-L12.** They sit in exactly the range everything shipped
      on 2026-09-07 targets, and they are now better evidence than more simulation.
      `bash tools/check_player_progress.sh` — at L25+ re-validate `make_char` against real saves;
      at L50+ the high-level balance work can finally be checked against real data.
- [ ] **Confirm the deck repair fired.** Five live characters carried bloated decks; the repair runs
      on their next login and logs `Deck repair: <name> reset to its N-card starter deck`.
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
- [ ] **Buff panel, party half.** Same strip for each party member, plus a STACKING indicator.
- [ ] **Card upgrade preview.** Hovering an upgrade shows YOUR card with it applied; once chosen the
      card is visibly different. Also: the damage estimate still counts only `power` picks
      (`_card_damage_multiplier`), so other upgrade families read as doing nothing.
- [ ] **Death replay / shareable combat log.** When a player dies, the chat message carries a
      clickable link to the combat log — ideally a replay — so everyone can see how it happened.
- [ ] **Combat layout at 1080p.** Monster ASCII still overlaps the player/companion cards by
      default; per-element resize exists but players should not have to reach for it.
- [ ] **Extend UI-scale registration** to the elements that still lack it (action bar, status HUD,
      inventory, market, crafting, sanctuary).

## Phase 4 — party (half-built; finish or cut)

- [ ] **Invite window** and **watch-a-teammate's-minigame** — the two remaining Party UI pieces.
- [ ] **Party fairness**: verify every member really receives combat rewards (especially equipment),
      rotate the leader between fights, consider splitting gathering/crafting/loot rewards.
- [ ] **"Party play isn't working properly"** (owner, 2026-08-26) — no repro captured. ASK for the
      symptom before investigating.
- [ ] **Leader logout must not strand the party.**

## Phase 5 — the dungeon arc (the big content direction)

- [ ] **Dungeon revamp** — owner wants dungeons changed "a good bit"; details not yet captured.
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
