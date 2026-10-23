# Phantom Badlands — Master Backlog

**The single ordered to-do list.** Read it before proposing what to work on; update it as work
lands. Items are ordered so each one's inputs are settled before it starts — working out of order
is what forces revisits.

> Closed (ticked) items live in `docs/archive/BACKLOG_closed_to_2026-10-15.md`; `tools/backlog_prune.py` moves new ones there.

History lives in `docs/archive/BACKLOG_journal_to_2026-09-07.md`. Search it before re-opening
anything: it records why several approaches were REJECTED, and re-proposing those is the most
common way to lose a session.

---

## ▶ START HERE - PLAN 2026-10-15 (written after v0.9.844; supersedes the "STATE 2026-10-14" and "WHAT TO DO FIRST TOMORROW" blocks lower down)

**WHERE THINGS STAND.** v0.9.844 is live (client + server). This session shipped the whole companion-team arc (item 14 S1-S5
+ party play): roles, tactics, up to four column companions (slots at L10/25/50/100), team targeting, healing/revive, the
Stable's Role Swap, role names on every surface, and teams in party fights. Also live: gold + Temper, the opening-blow cap,
the +/-5% level band. HELD, not shipped: the tougher monster curve (see item 9).

**THE RULE THAT KEEPS US FROM CREATING WORK: ONE CHAIN RUN, AT THE END OF THE POWER CHANGES.** Anything that changes how
strong a player or a monster is must land BEFORE the calibration chain, and the chain runs once. Every item below is
sorted by that, not by size. Doing a power change AFTER the chain is what forced the re-runs this month.

### WAVE 0 - housekeeping that pays for itself (small; do first)
- [ ] **OWNER LOOKS AT THE LIVE SCREENS** (only the owner can; real-client screens are on the private page https://claude.ai/artifact/5PfKkaBpe4NzGtpjJcZGMY and the harness can capture any other team scene on request): Companions panel Team section, a solo fight with a team,
      a pair fight, the Stable's Role Swap. Screenshots from the harness are in `claude_screenshots/team_*.png`; a real-client
      look is the one thing no probe can give. Anything that looks wrong is fixed before more is built on it.
- [x] **PRUNE THIS FILE** (DONE 2026-10-15: 10,939 -> ~5,400 lines, 283 closed items in `docs/archive/BACKLOG_closed_to_2026-10-15.md`, `tools/backlog_prune.py` refuses if an open item would move). It is 10,000+ lines, mostly ticked history, which is why it is hard to plan from and why items get
      re-offered. Move every ticked block to `docs/archive/` (one dated file), leave the open items and this block. Mechanical;
      `tools/backlog_audit.py` must give the same open-item list before and after.
- [x] **TEST DEBT** (DONE 2026-10-18): the full run was 391 probes / 82 failures. 62 were measurement scripts with no verdict -> 58 moved to `tools/audit/` (with 4 more that need a renderer or live state), 4 given a PASS line; 17 were stale probes (Temper replaced the blacksmith text, gold pile band, Role Swap passes the level, fixtures missing persistence/world/chunk_manager, a broken file) and are fixed; 2 were REAL bugs (below). `probe_run.py --repeat N` lists flaky probes. Remaining intermittent: none found in 10 repeats.
      REAL BUGS FOUND: (a) Cursed Coin tails / curse scrolls were eaten by an auto-resolved trivial encounter (the debuffs apply after the trivial check) - fixed in `_encounter_is_trivial`; (b) `_check_dungeon_spawns` read `instance.spawned_at` directly and errored on an instance without one - now `.get`.
- [x] **FINISH WHAT THIS SESSION LEFT OPEN** (DONE, unreleased): role/tactics line on the beside-you card; team HP bars held during paced playback; 'Claim Title' at the High Seat (built, not clicked through on screen). The party slot split feel awaits the pair playtest below.
- [ ] **PLAYTEST PARTY PLAY** (item 8): built and probed, never played with two humans. Owner + one other, ten minutes.

### WAVE 1 - the power inputs, designed TOGETHER, built in dependency order (no chain yet)
These all change power or the money behind it, so they share one design pass and one calibration:
1. **[BUILT 2026-10-20, unreleased (v0.9.847 in master): valor ledger, gold telemetry, Sanctuary points by play, Role Swap in kills, the Master Smith; STILL OPEN: companion feeding sink, surplus conversion (Wave 3), Sanctuary ladder repricing from measured points/hour, Master Smith in the balance model. DESIGN: `docs/design/economy.md` - owner ANSWERED Q1-Q4 2026-10-20: gold gets a big saved-up sink (Master's Commission), no companion upkeep, surplus NPC pays sellers less, Sanctuary one unlock per 20-30 min of play - NB Sanctuary costs Baddie Points earned only at DEATH, so pacing needs accrual-while-playing (doc 4.7, awaiting owner yes); ledger + gold telemetry BUILT (valor_ledger probe)]** **ONE ECONOMY DESIGN** for the four items that are the same question ("what do players spend on, and where does it
   come from"): item 14 S5's economy half (Role Swap price, companion upkeep), "Real sinks for excess eggs and companions",
   THE VALOR ECONOMY REALM-WIDE, and THE WORLD CONSUMES MATERIAL SURPLUS. Design doc first (`docs/design/economy.md`), then
   build. Gold prices (Temper, Role Swap) are unmeasured first guesses and are tuned HERE, once, not per feature.
2. **ITEM 11 VARIETY** - **OWNER DECISIONS 2026-10-22 in `docs/design/variety_item11.md`** (named traits on ~1 in 3 monsters, mostly stats with a few behaviours, mean-preserving; companions inherit one trait and roll one; boards: 3-4+ different species, trait hunts, rotating themes; dungeon cards: every class 2+ worth swapping in, all 53 tagged for triggers). **BUILT 2026-10-22 (unreleased): traits, board species variety, themes (families), hourly trait-hunt bounty, companion perks, dungeon card tags; the dungeon card power pass is DONE (power x2, engine feed +2, Wizard x3; doc section 7). OPEN: terrain themes, `dungeoncardswap` at tiers 2/4/6+.** (rolled monster stats, companion variety/rolls, quest-board variety). 11(c) must follow item 14
   (roles) - done. Design first; the rolls change power so they belong before the chain.
3. **PATHS REVAMP** (class-specific, less conditional) and the **DUNGEON CARD POWER PASS**: both change player power and
   both are blocked only on an owner design answer. Ask once, build once.
4. **THE REMAINING 24 CYCLICAL BURSTS** - **DONE 2026-10-22, unreleased:** seven more damage bursts now wind up (Soul Siphon, Sonic Echo, Hatchling Swarm, Infernal Curse, Primordial Roar, Divine Punishment, Death Mark); the other 16-17 were each DECIDED not to be bursts (heals, auras, stacking ticks, debuffs; reasons in `a_telegraph_is_answerable` section 4, which now fails on any cyclical ability that is neither). Must precede the chain, and does.

### WAVE 2 - the balance batch (item 9): ONE run
`-- preflight` first, then speciescal, refcal, rolecal ONCE each (use `--budget=5400` for rolecal). Fold into it, in this order:
(a) the held candidate curve - decide it with the team in the model (measured: with a full team the candidate is no worse
than today's game with ONE companion; under-geared characters, who the sim gives no companions, are worse - decide whether the
model should give them one BEFORE the run); (b) per-class death rates (Wizard 31% at own level, Sage/Barbarian/Ranger) -
per-class levers only, a global buff is cancelled by the refit; (c) empowered difficulty; (d) the gold price tuning from Wave 1.
Then read the death log for a week before touching anything (live population is ~5 accounts, so the sim and the owner's play
are the evidence).

### WAVE 3 - world and content (each is large; none changes power, so none waits on the chain)
In this order, because each one's input is the one before it: **Player Phantoms client surfaces** (built, held behind
`PHANTOM_POSTS_ENABLED := false` - this is also the long answer to "no farmable ground") -> **Living world / rework the posts**
(explicitly sequenced after Phantoms) -> **Dungeon revamp B + dungeon questing replaces the overworld quests** (B waits on the
card power pass in Wave 1) -> **post-to-post road travel** -> **Sanctuary redesign** -> **item 12 restarts/events** (needs the
living world) -> **THE UNBURIED** (needs the owner's permadeath decision) -> Prize Shuffle gathering/crafting, sprite scale.

### OWNER DECISIONS 2026-10-15 (answers to the five below)
2. **Under-geared characters have AT LEAST ONE companion** - DONE in the simulator (`make_char`: only `gearless`, a character created today, has none). MEASURED, death % per fight at L30 / L100 / L500 (270 fights per cell): **average gear** - shipped curve + one companion 3.0 / 2.2 / 0.0, + full team 0.4 / 0.4 / 0.0; CANDIDATE + one companion 1.5 / 3.0 / 0.0, + full team 2.2 / 0.4 / 0.0. **under-geared** - shipped + one companion 3.0 / 3.0 / 0.0, + team 1.1 / 0.7 / 0.0; CANDIDATE + one companion 1.1 / 3.3 / 1.1, + team 0.7 / 2.2 / 0.0. **So the candidate curve is no worse than the shipped one once everyone has a companion (differences are within the ~1.7-point noise) - the shipping condition is MET from L30 up.** STILL WORSE on the candidate: a brand-new GEARLESS character with no companion (L3 0.0 -> 1.9, L10 5.2 -> 7.8) - decide a starter companion or leave the early game on its own table before shipping. Data: `docs/balance/data/riskcurve_270_everyone_has_a_companion_*`.
4. **Wave 3 starts with PLAYER PHANTOMS.** 5. **Permadeath is staying** - THE UNBURIED and the economy design may assume it.
1 (party slot split) was elaborated to the owner 2026-10-18 and awaits the keep-or-make-flexible answer; 3 (paths / dungeon-card design) is a back-and-forth design conversation, questions sent 2026-10-18.

### FIGHTER OPENING STANCE + NINJA - measured 2026-10-20 (`-- classrisk --stance=1.0|0.5|0`, data `docs/balance/data/classrisk_stance_*`)
Owner asked why the Fighter gets 60% DR + defence free at every fight start. 150 fights/cell, every class has a companion, other eight rows byte-identical across runs (control holds). **Win % shipped stance vs none (average gear, L10/30/100/500): Fighter 100/97/85/86 vs 95/89/75/68; Barbarian 96/85/75/75; Paladin 94/79/70/63.** Without the stance the Fighter sits with its Warrior siblings; with it the Fighter is the safest class at L10-30 (0.0-0.7% death) and +10-18pp at L100-500. Deaths at L100-500 are 3-5%, not lower than others. Stance 0.5 lands in between (99/94/79/69). NOT CHANGED - owner decides (trim to 0.5 as a per-class change inside the Wave 2 chain run, or keep).
**NEW FINDING: the Ninja wins only 6-44% of fights at every level and dies 6-18%** (next worst class 51-70%) - a broken class in the sim; check the card/policy first (instrument), then the class. Put in Wave 2 per-class work.

**FIGHTER STANCE HALVED + NINJA RESOLVED - 2026-10-20 (owner ruling).** (1) The Fighter's free opening stance is now half strength
(`WARRIOR_STANCE_RATIO` 1.0 -> 0.5: 30% damage reduction for 4 rounds) and is NAMED: the combat log says "Fighter's stance: you open
braced..." and the status chip / mitigation list show it as "(Fighter's stance)". General rule from the owner: **any buff the player did
not cast must show where it came from.** Mechanism: `Character.add_buff(..., source)` + `get_buff_source()`; companion buffs are tagged
with the companion's name; engines (Momentum/Volatility/Read) and CON were already listed. Probe: `free_buffs_name_their_source`.
STILL TO SWEEP for the same rule: racial/class passives and path effects that act silently in the damage path. (2) NINJA was an
INSTRUMENT defect, not a class defect: `_finisher_is_ready` gated Assassinate on `assassinate_chance >= 45`, which cannot be true since
the 09-08 rework (cap ~26%), so the finisher fired only from the "anything castable" fallback at 1-4 Read and zeroed its own bank.
Fixed in the simulator (bank to Read 6 like its siblings; fallback never burns the finisher). Ninja average gear 44/38/11/8 -> 81/84/65/72
win% at L10/30/100/500; Grifter/Ranger rows byte-identical. Data: `docs/balance/data/classrisk_stance_0.5_ninja_policy_fixed_2026-10-20.txt`.
Not yet shipped (needs a release); `-- cardtrace --class=X --level=N` prints a turn-by-turn trace for any trickster.

### OWNER DECISIONS NEEDED (batched so they cost one conversation, not six)
1. Is a pair getting ONE teammate each right, and is "none in a party of 3+" acceptable?
2. Should 'under-geared' characters in the model have companions (changes whether the candidate curve can ship)? **ANSWERED 2026-10-20: YES - players get their first companion after the tutorial, so the model gives gearless characters one.**
3. Paths revamp and the dungeon card power pass: the direction (each blocked only on this).
4. Which Wave 3 item first, once Wave 2 is done.
5. Permadeath: is it changing? (gates THE UNBURIED and parts of the economy.)

---

## ⚑ OWNER DIRECTION 2026-09-13 — the world reshape and what it exposed

All of this came out of the distribution work. Recorded before starting any of it.

### BLOCKING the release


### NEXT, in the order the owner raised them





- [ ] **POST-TO-POST ROAD TRAVEL — ACCEPTED by the owner 2026-09-13 <!-- audited: 2026-09-19 --> Verified still open: nothing in server/ or client/ implements travel between posts.** (held as a separate
      decision, and answered separately).
      Standing on a road at a discovered post, offer travel to another discovered post along it,
      fast-forwarded with a chance of interruption. It is the most direct answer to "travel is
      long" and it is also the one that could most easily devalue exploration, which is why it
      should be decided on its own rather than bundled.
      **Owner's acceptance set the price: it costs TIME AND RESOURCES, not nothing.** That is what
      keeps it from devaluing the walk - arriving with a drained bar is a different arrival than
      teleporting in fresh.

- [~] **AUDITED 2026-09-13, four pieces need replacing; replacements NOT yet chosen.** Owner:
      *"some of the art we may want to use an alternative of (we may want to audit those pieces
      individually)."* Rendered all fourteen on the biome ground each actually sits on
      (`claude_screenshots/gatherable_art_audit.png`).

      **Reads well, leave alone:** brambleberry, stone, ore_vein, flower, mushroom, swamp_lily,
      cactus, ice_bloom - each distinct in silhouette AND colour against its ground.

      **Needs an alternative, and they share one cause:** `tree`, `bush`, `dense_brush`, `reed`
      and `mountain_herb` are ALL cut from `green_forest_v2`, which is why they are all the same
      green.
      * **tree vs bush is the worst** - both are leafy green domes, near-identical at a glance,
        and they are different JOBS (chopping vs foraging). A player cannot tell which they are
        standing on.
      * **mountain_herb** is dark green on brown rock - almost invisible.
      * **reed** is green strokes on swamp green - blends into the ground.
      * **dense_brush** reads as flat texture rather than an impassable thicket.

      **An automated candidate search was tried and abandoned rather than trusted:** filtering
      pack cells by "has a transparent margin" returns terrain edges, scaffolding and crates, not
      plants - alpha cannot tell a herb from a transition tile. Picking these needs the indexed
      contact sheet (`tools/tileset_contact_sheet.py <pack> --rows a-b`) and an eye. Sheets for
      `farmlands_v3` are already rendered in claude_screenshots.
      Was: **Audit the gatherable ART piece by piece.** Owner: *"some of the art we may want to use an
      alternative of (we may want to audit those pieces individually)."* Same procedure as the
      room floors: render them together, look, replace what does not read.

## ⚑ WHERE THE LIST STANDS — AUDITED 2026-09-19, and the audit is now a script

✅ **AUDIT COMPLETE 2026-09-19 — 51 open became 25.** Every flagged item was verified against the
CODE, not re-read. The list is now: **25 genuinely open, 280 done, 23 awaiting the owner or marked
as duplicates.** Zero strong suspicions remain.

What the 51 actually were:
* **6 already done or duplicated** — Magic Bolt (resolved 2026-09-07, its copy outlived it),
  53 dungeon cards (= the card POWER half), Minigame variety (= Prize Shuffle), the Phase 2 sprite
  scope (all 14 gatherables have sprites), the Launcher revamp (self-update + inbox both shipped),
  and Crafting Reassessment (steps 1-9, ~950 lines, no open marker).
* **13 not work at all** — feel checks, watch notes, look-and-says, one blocked on GitHub, one
  deferred by the owner, and two PROPOSALS OF MINE that had been sitting in the list as though the
  owner had asked for them (CRT/scanlines, combat gambits). Those now read `- [→]`.
* **1 seen in pixels** — the dungeon key was always built; only the evidence was missing, and a
  capture taken while chasing something else finally showed it.
* **The rest verified genuinely open** and vouched with `<!-- audited: DATE -->`, each checked in
  code: `path_database.gd` still holds three ARCHETYPE trees; `HOUSE_UPGRADES` still carries the
  untouched ladder to 80,000; `QUEST_VALOR_PER_LEVEL` is still the interim 3.5; no market-surplus
  conversion exists; nothing varies a card's art by upgrade.

⚡ **THE LIST WAS ~40% WRONG AND HAD BEEN FOR DAYS.** The owner was offered three items that were
already built and said: *"it still has stale information despite me asking a dozen times for it to
be updated as we complete these things."* That is not a memory failure to apologise for, it is a
missing check - and this file's own rules already say *"a check nobody runs is not a check."*

**`python tools/backlog_audit.py`** now flags open items whose own text says DONE, whose named
probe already exists, or whose named symbols are all present - and duplicates. Run it BEFORE
choosing work. First run flagged 22 of 51.

Corrected on that first pass:
* **CRAFTING REASSESSMENT** - steps 1-9 all complete, no open marker in ~950 lines. Unticked for a
  day, and one of the three offered to the owner as available work.
* **POST SERVICES** - two of three parts shipped (healer, merchants).
* **INVENTORY BLOAT** - substantially resolved; the pouch trigger is measured and has not fired.
* **AN UPGRADED CARD SHOULD LOOK UPGRADED** - said "still not started"; the hover preview exists.
* Two entries marked "(superseded)" were still open, and the valor pass was listed twice.

The root cause, stated so it is not repeated: lines were ticked when work was DONE on them, and
never verified when work was CHOSEN from them. The decay therefore concentrated exactly where the
list is read.

## ⚑ WHERE THE LIST STOOD — recounted 2026-09-19 after v0.9.816 (the balance instrument arc)

Counted mechanically (`- [ ]` vs `- [x]` across this file), not estimated. **2026-09-19: 52
open, 265 done.** The balance batch is largely spent - the v0.9.816 chain carried five queued
items through with it - and what it left behind is two OPEN QUESTIONS rather than tasks (see the
NEXT SESSION block): why `species_power` only ever strengthens, and whether L5 actually plays as
rough as it measures. Both want live data before code. **The working order is
the RECOMMENDED ORDER in the NEXT SESSION block.** The breakdown below is from 2026-09-13 and is now approximate — the onboarding arc closed a large share of
"everything else" between then and now.

    Phase 5 - the dungeon arc            16   the big content direction
    Phase 3 - combat UX debt              6
    Phase 8 - later / unscheduled         5
    Owner direction (world reshape)       2   both are MY suggestions awaiting a yes/no
    Phase 4 - party                       3
    Phase 6 - realm meta and sinks        3
    Phase 3.45 - sprite interiors         3
    everything else (7 sections)         12

**The dungeon arc is the bulk of what remains, and it is the owner's stated big direction.**
Nothing else has 16 items. Two of the three "owner direction" entries are proposals of mine that
have never had a yes or no - trivial-encounter auto-resolve and post-to-post road travel - so they
are the cheapest things on the list to retire, in either direction.

## ⚑ OWNER DECISIONS 2026-09-13 (third batch) — the dungeon arc, unblocked

Asked because the arc had run out of defects and into design. All four answered.




- [ ] **PARTY PLAY — HALF TWO (the mechanics underneath the model above): independent movement + join-in-progress combat.**
      <!-- audited: 2026-09-19 --> Verified still open: independent movement and join-in-progress
      are NOT built. Half one (dungeon party combat) is live, which is what trips a DONE-word scan. (Half one, dungeon
      party combat, is built and live; the onboarding guide it blocked has shipped.) Original title:
      PARTY PLAY IN DUNGEONS + JOIN-IN-PROGRESS COMBAT.
      This is what *"party play isn't working properly"* (2026-08-26, never reproduced) actually
      meant. Owner 2026-09-13: *"likely regarding no support for it in dungeons and possibly
      making it where players can navigate themselves but then join each other when they are in
      battle (would need a visual indicator on the map to show a party member is in battle and a
      way to handle a party member joining the combat etc)."* It was filed as a bug for a year;
      it is two pieces of design. Re-filed as such.

      **✅ HALF ONE IS COMPLETE - dungeon party COMBAT SHIPPED. (Re-verified 2026-09-19.)**
      The text below said dungeon combat was missing and it is now STALE: `_try_start_dungeon_coop`
      and `_start_guided_dungeon_combat` both call `start_party_combat_simul`, and the
      *"legacy shared party combat disabled"* comment it quotes no longer exists anywhere in
      `server/server.gd`. Confirmed from live the same day - the owner hit a party-combat bug at
      the starter dungeon boss, which is a code path that cannot run unless dungeon co-op exists.
      Kept for the history and for the note on how it was got wrong. **(Corrected 2026-09-13 - the
      first version of this item said dungeons had no party support at all, and that was wrong.)**
        * Entry WORKS. `handle_dungeon_enter` has an `if _is_party_leader(peer_id)` branch that
          validates every member, enters the leader, then places each follower on an adjacent
          tile and appends them to `instance.active_players`.
        * Movement WORKS. `_move_party_followers_dungeon` snakes followers behind the leader and
          is reached from `handle_dungeon_move`.
        * **COMBAT does not.** Both dungeon combat paths carry the same comment -
          *"v0.9.732 - legacy shared party combat disabled pending rebuild (see
          trigger_encounter). In dungeons the leader just fights solo (card-based)."* - and call
          `combat_mgr.start_combat(peer_id, character, monster)`. The #64/#76 co-op rebuild that
          replaced it was only ever wired into `trigger_encounter`, the overworld random
          encounter. The dungeon paths were left on the disabled-legacy note and never revisited.
      So a party walks into a dungeon together, moves through it together, and then fights every
      monster in separate solo combats. That is the reported symptom, and it is one wire, not a
      subsystem.

      **How I got it wrong, because the shape recurs:** I grepped a 158-line window from the top
      of `handle_dungeon_enter` and the party branch sits at line ~30011, just past it - then read
      "no match" as "not implemented". A bounded search that finds nothing proves nothing about
      what lies outside the bound. Compounding it, I searched for `in_dungeon = true` when entry
      goes through `character.enter_dungeon(...)`, which sets the flag inside `Character`.
      See [[feedback_verify_before_building]] - this is the same failure it was written for.

      **Half two - independent movement, then join the fight.** Today the party is
      MOVEMENT-LOCKED: `_party_follower_locked` blocks a follower from moving, hunting, resting,
      gathering or crafting anywhere except inside a post, and `_move_party_followers` drags them
      in formation. Co-op combat only fires when the LEADER hits a monster with 2+ members free.
      The owner wants the opposite shape: everyone walks their own path, and combat is what pulls
      them together. That needs three new things:
        1. **a map indicator** that a party member is in battle, and where;
        2. **join-in-progress** - adding a member to a fight already running. Nothing supports
           this today; `start_party_combat_simul` builds `member_states` once at the start and
           `_party_all_submitted` gates the round on the member list as it stood then. A joiner
           has to enter between rounds, not mid-round, and the monster's HP was already
           multiplied by the party size at start - a late joiner must not silently double it.
        3. **travel distance rules** - who is close enough to join, and what happens to someone
           who is half a map away.

      Build order: dungeons first (it is the blocker, and it is the smaller piece - the co-op
      branch already exists and wants lifting out of `trigger_encounter` into something both
      paths call), then join-in-progress. Unlocking independent movement BEFORE join-in-progress
      exists would make parties worse, not better: everyone would scatter with no way to regroup
      in a fight.

      **✅ HALF ONE IS BUILT (2026-09-13, unreleased).** `_try_start_dungeon_coop` +
      `_party_dungeon_after_combat` in `server/server.gd`, wired into BOTH dungeon combat
      starters. Gated on same instance AND same floor, which the overworld has no equivalent of.
      Probe: `tools/probe/dungeon_party_combat.gd`, 30 checks, run against real functions on a
      real `CombatManager` and proven to fire by deleting the call site. The onboarding guide NPC
      is unblocked. **Still open here: half two (independent movement + join-in-progress), and
      two gaps this did not close** - flock follow-up fights still only come out of the SOLO
      victory path, so a party fight never chains into one (the same gap the overworld has, and
      the standing *"party flocks are not wired"* item), and none of this is playtested.


- [ ] **DUNGEON QUESTING REPLACES THE OVERWORLD QUESTS ENTIRELY.** Not a supplement. ⚑ The risk
      named when the choice was offered still stands and has to be designed around: a brand-new
      character needs a dungeon it can clear immediately, or the first hour empties out. Whatever
      replaces the overworld quests must reach down to level 1.

<!-- The owner's acceptance of both proposals is recorded ON the two items themselves, higher up
     in this file, where their design detail already lived. A third copy stood here until
     2026-09-13; the Dungeon Atlas was once tracked as three separate tasks in three places and
     this is the same shape. What the acceptance ADDED to those items, and is now folded into
     them: auto-resolve grants FULL rewards, not token ones; road travel costs time and
     resources rather than being free. -->




- [~] **⛑ INSTANCED CARDS — two of the three complaints ANSWERED 2026-09-16, one still open.**
      Owner, live 2026-09-14: *"Players aren't seeing or understanding what cards they are getting
      for completing dungeons. Sometimes they notice that two upgrade screens pop up back to back
      for the same card but it's nowhere to be found in their deck. They also have no way to
      differentiate between them even if it was."*

      Driven through the real model by `tools/probe/card_reward_visible.gd`:

      - [x] **"Two upgrade screens for the same card" is NOT a double grant — it is BY DESIGN, and
            it was unreadable.** Measured: a legacy card owned 3x with 60 uses and no stored picks
            migrates to three instances each carrying 60 uses, so each independently owes 2
            milestones — **6 popups for what the player sees as one card**. Every one is an upgrade
            they are genuinely entitled to (per-instance levelling is the feature), so the defect
            was purely that nothing said WHICH copy.
      - [x] **And `_card_copy_label` had been added to some surfaces only.** The 2026-09-15 fix put
            it on the milestone-overlay title and two other spots but missed
            **`_show_rank_choice_popup`** — the actual screen a player is looking at when two
            arrive — plus `show_card_desc_box` and `_get_ability_tooltip`. Textbook "a rename
            touches SEVEN surfaces". All three now carry it, and the probe SWEEPS client.gd for
            any player-facing card label that forgets, so it cannot land partially again.
      - [x] **The grant itself is sound.** One grant adds exactly one copy, and a fresh copy owes
            no milestones, so it raises no popup. The roll was never the problem.
      - [x] **Complaint 1 was ALREADY FIXED and never ticked — verified by looking, 2026-09-16.**
            Commit `8a5a77b0` (2026-09-15, the day AFTER the report) made the completion screen
            speak either way, naming the odds and the card. Confirmed on screen with
            `--shots=dungeoncard`: the banner reads *"★ RARE CARD DROP! ★ +1 copy of Fortify
            (deck ×1/3)"* in magenta on the wide page, impossible to miss. Shipped-but-unticked
            is its own trap; the probe exists now so the next check is a minute, not a guess.

## ⚑ RELEASE CADENCE — there are LIVE PLAYERS now (owner, 2026-09-13)

*"We've got some live players now so we want to limit our releases."* A release restarts the
server and disconnects everyone. **Batch the work; deploy rarely.** Ship immediately only for data
loss, a crash, something that permanently breaks a character, or a live regression we caused.
Building and gating is free - do that as often as you like. Creating the release is not.

**⛑ 2026-09-13 — THE HELD BATCH NOW CONTAINS A CHARACTER-BREAKING FIX, which meets the owner's
own bar above.** Sanctuary companions were being DEMOTED to a stale level on their first kill and
the Sanctuary then kept the lower number (see `tools/probe/companion_level_survives_death.gd`).
That is permanent loss of earned progress, happening to live players every time they check a
companion out. The rest of the batch is still not urgent; this one is. **Owner's call to deploy.**

**HELD, built and gated, not deployed:** v0.9.786 - the tile audit (well/fountain were the same
image, post_marker 4.4 from quest_board, blacksmith 13.0 from healer and the same JOB, pylon drew
nothing), marsh + aerie dungeon markers. All art; none of it urgent.

## ⚑ INVENTORY BLOAT — MEASURED ON LIVE, AND THE POUCH IS NOT NEEDED YET (2026-09-18)

Owner: *"Items and tools can buildup and takeover your backpack slots. We may want to have a
separate item pouch or unlimited items... for inventory bloat we need to make autosalvage easy to
understand and setup."*

⛑ **THE LIVE POPULATION SAYS THE POUCH WOULD SOLVE A PROBLEM NOBODY HAS.** 18 characters on the
real server: **median 2 of 40 slots used.** The fullest is a level-48 at **28/40**, the next at
24/40. Crafting materials have always lived in their own unbounded dict, so they were never the
pressure. A pouch is a change to the item model, the UI and every delivery path — for a cap nobody
is within 12 slots of.

**But the fullest character shows WHICH items accumulate**, and it is not gear:
`ring_arcane:4, tool:2, scroll_target_farm:2, scroll_monster_select:2` — utility. And the crafting
arc adds four Scribe items, returned runes and commissioned deliveries, so the pressure rises.

**→ Filed with a trigger, not cancelled: build the pouch when a real character passes ~32/40.**
Re-measure with `bash tools/check_player_progress.sh`; the probe prints the threshold.

**✅ THE OTHER HALF SHIPPED — auto-salvage now shows what it would DO.** The screen stated the rules
clearly and never the consequence: a player could read *"Items up to Rare will be auto-salvaged"*
and have no idea whether that meant two items or twenty. It now reads:

```
Right now this would salvage 3 of your 11 items:  Rusty Blade, Cloth Cap, Worn Ring
(Auto-salvage only runs on NEW drops — these are shown so you can see what the rule catches.)
```

⛑ **The preview runs through `Character.would_auto_salvage`, the SAME function the server destroys
items with.** A preview computed from a client-side copy of a destructive rule is the one duplicate
that can tell a player their gear is safe while the server eats it.

⛑ **AND EXTRACTING IT FOUND A LIVE DIVERGENCE.** There are two auto-salvage paths asking different
questions, and they had different rarity ceilings:

| path | question | ceiling |
|---|---|---|
| `_should_auto_salvage_item` | salvage this **incoming** drop? | up to **legendary** |
| `_try_auto_salvage` | destroy an item I **already own** for room? | capped at **rare** |

So a player who set *Legendary* had epics auto-salvaged on pickup but never sacrificed for space —
the same setting meaning two things depending on which code you reached. The stricter floor for
destroying owned gear is **right**, so it is kept and is now
`Character.AUTO_SALVAGE_MAKE_ROOM_CEILING` with the reason written down, instead of a truncated
three-entry array sitting next to a five-entry one.

Probe: `tools/probe/inventory_pressure_and_autosalvage.gd` — nine behaviour cases run against the
real rule, proven by injecting "locked items are no longer protected".

## ⚑ THE POST ART PASS — SHIPPED 2026-09-18 (owner-reviewed, on screen)

Owner walked the posts and flagged nine things. **Every one was right**, and three were fragments
rather than bad choices — the earlier multi-tile pass fixed 19 tiles and left these behind.

| tile | was | now |
|---|---|---|
| **post door** | narrow wooden slab | `green_buildings (29,34)` — stone arch, **doors open** |
| **quest board** | a roadside signpost, 1 cell | `interiors (3,15)` 3×3 — a board covered in pinned notices |
| **post centre** (`post_marker`) | crossed swords with the tips **cut off** | `sun_city (23,16)` 3×3 banner |
| **market** | a fishmonger's slab — fish and a cleaver | `interiors (8,12)` 3×2 stocked shelf of wares |
| **apothecary** | a copper alembic | `interiors (8,10)` 3×2 shelf of potion bottles |
| **blacksmith** | "a big stove" | a **person** (`5_4`) |
| **healer** | a chest with a cross | a **person** (`m3_4`) |
| **cartographer** | a literal rectangle of wall texture | a **person** (`m2_7`) |
| **anvil** | — | new; the smithing station the blacksmith no longer has to be |
| **inn** | duplicate of the healer | **cut** |

⛑ **THE NPC PRECEDENT WAS ALREADY IN THE BAKER, UNUSED.** `bake_warden` says it outright: *"He is
a PERSON, so his tile is a person — taken from the same overworld sprite set the players use rather
than drawn as a piece of furniture."* The Warden got that treatment and the other three did not, so
you walked up to a **stove** to talk to a smith. `bake_person` is that routine extracted, so all
four scale and anchor identically.

⛑ **THE DOOR IS THE OPEN ONE FOR A MECHANICAL REASON.** `world_system` gives `door`
`blocks_move: false` — players walk **through** it — so the handsome shut pair would have drawn a
barrier across a tile you are meant to step onto.

⛑ **THE INN WAS MEASURED BEFORE IT WAS CUT.** `_handle_inn_interact` was one line calling
`handle_trading_post_recharge` — **the same function the healer calls**. Two tiles per post doing
one job. And the migration written to strip it from the 120 saved posts was then deleted: a saved
post stores only geometry and derives its stations from the list every read, so the cut reaches the
live world immediately and that code would have walked a dictionary that does not exist.

⛑ **PICK SPANS BY RENDERING THEM, NEVER BY READING COORDINATES.** The anvil went in **one column
off**, splitting the grey anvil and gluing the left edge of the brown one to it — the exact fault
this whole pass exists to fix. Every pick after it was rendered side by side first.

**ASCII art also fixed:** the blacksmith and healer stopped re-rolling a new face every visit. The
persistent variant already existed and these were the last two callers of the random one, so a
wandering merchant kept his face while the smith you visit daily did not. Seeded on post + role.
The **rescue NPC keeps random art on purpose** — that one *is* a different stranger each time.

## ⚑ TEACH THE GATHER → CRAFT LOOP — REFERENCE HALF SHIPPED 2026-09-18

*"There should be a tutorial or help guide that introduces or walks players through how to
efficiently make their equipment and how to further improve it, gain the affixes it wants, reroll,
etc. In general the gather, craft loop."*

**This is the last piece of the crafting arc, and it is deliberately last:** the loop it has to
teach has been changing all day, and a guide written before the content settled would have been
wrong by evening.

⛑ **MEASURED, so the scope is not a guess.** The existing `CRAFTING & GATHERING` help topic is
**1,242 characters** and covers exactly two things: salvage, and "stand on a resource and press R".
Checked against the concepts a player actually needs:

| concept | in the help today |
|---|---|
| runes / enchanting / affixes | ✗ |
| rework, reroll | ✗ |
| commission (NPC or player) | ✗ |
| quality, Masterwork, temper, boost | ✗ |
| specialist, commitment | ✗ |
| disenchant, transmute | ✗ |
| tools | ✓ (the only one) |

**14 of 15 core concepts are unmentioned**, and most of them either shipped today or were reworked
today.

**✅ THE HELP HALF IS DONE.** One thin topic (**1,242 chars**, covering salvage and "press R")
became three — **GATHERING**, **CRAFTING**, **IMPROVING YOUR GEAR** — at **5,132 chars**, and all
15 concepts the audit listed as missing are now covered.

⛑ **EVERY FIGURE IS GENERATED, and the first draft broke that rule immediately.** The entry above
warned that *"any figure typed into help text is a second copy waiting to go stale"* — and I then
typed *"about 5% to 95%"* and *"about two thirds"* as prose. `_craft_skill_figure()` now reads them
off `roll_quality_detailed` at display time, and the rework cap and the commit bonus come from
`MAX_AFFIX_REROLLS` and `COMMITTED_JOB_XP_BONUS`. The probe fails if a literal comes back.

⛑ **AND THE REWRITE DROPPED SOMETHING THE OLD TEXT HAD.** Tools were the ONE thing the thin topic
covered, and my three new topics lost them — the probe caught it. They are back, with the part that
actually matters: a tool that runs out of durability is **destroyed**, a spare auto-equips, and
**nothing repairs one**.

The guide is honest about the two counter-intuitive rules, as the entry required: a **Rework can
come out worse and it stands**, and a **commission is always Standard quality** so a real crafter
beats it.

Probe: `tools/probe/crafting_help_covers_the_loop.gd`.

**✅ THE WALKTHROUGH HALF IS DONE TOO — v0.9.811. THE CRAFTING ARC IS CLOSED.**

⛑ **AND THE FIRST THING THE AUDIT FOUND WAS A HINT THAT TAUGHT NOBODY.**
`_maybe_send_rework_hint` was written with a persisted `seen_rework_hint` flag, parsed, and had
**no call site at all** — so the one rule in this arc that will otherwise read as a bug (*a Rework
can come out WORSE, and it stands*) was explained to no one. A session note said it was wired. It
was not. That is the "capability with no door" defect for the eighth time in this arc, and it is
now a check rather than a memory.

`tools/probe/every_hint_has_a_moment.gd` walks every `_maybe_send_*_hint`, counts its CALLS (not
its mentions — the first cut matched the declaration and passed the one that was missing), and
confirms its `seen_` flag is persisted. A hint that fires every login is worse than one that never
does. `_maybe_send_progression_hint` is exempt **by name with the owner's quote**: it was retired
deliberately (*"I really don't like the progression reminder popup, it's intrusive"*) in favour of
the pulsing `Stats +N` marker.

**The loop, moment by moment, all five now firing:**

| step | moment | hint |
|---|---|---|
| 1 gather | first catch / ore / log | `_maybe_send_gather_hint` (was live) |
| 2 craft | first bench | `_maybe_send_crafting_hint` (was live) |
| 3 improve | first **salvage** | **new** — gear you outgrow IS the materials; lock what you keep |
| 3 improve | first **rune** crafted | **new** — a rune is an affix in your pocket; disenchant returns them |
| 3 improve | first **Rework** quote | **wired** — it can roll lower and it stands |
| 4 cannot make | first commissionable or locked row | `_maybe_send_commission_hint` (wired earlier today) |
| 5 somebody pays | first `◆ wanted` row you can fill | **new** — the Valor is escrowed; your quality is yours |

The reference half is what a player goes looking for; these are what reach a player who does not
know to look.

**⛑ USE THE TWO SURFACES THAT ALREADY EXIST — do not build a third.**
* `show_help()` topics (~30 of them, keyword-searchable) — the reference half. Extend
  `CRAFTING & GATHERING`, and probably split it: gathering, crafting, improving an item.
* `client/tutorial_hint_panel.gd` — the existing one-shot modal for first-time teaching, with a
  `disable_tutorial` flag already respected. This is the *walkthrough* half: fire a hint the first
  time a player stands at a bench, first salvages, first sees a rune, first hits a `Wanted` job.

**The loop to teach, in the order a player meets it:**
1. **Gather** → materials have a destination (every one of the 131 now does).
2. **Craft** → the bench answers questions now: *Can Make / At My Skill / Wanted / All*, and the
   detail screen says what the item is and how it compares to what you wear.
3. **Improve it** → runes add affixes; **Rework** trades a stat you don't want for one you do
   (5 per item, and it can roll lower); reforge rerolls within a fixed band.
4. **What you can't make** → commission it from a post NPC, or post the job for a player.
5. **Specialise** → committing pays **+50% XP**, unlocks that trade's recipes and its field
   service, and costs you nothing elsewhere.

**Two things the guide must be honest about**, because both are counter-intuitive and both will
otherwise read as bugs: a **Rework can come out worse** (37% do), and a **commission is always
Standard quality** — a real crafter is better.

⛑ **AND IT MUST BE GENERATED WHERE IT CAN BE.** Numbers in this guide — the rework cap, the
commission fee curve, the +50%, quality odds — are all constants that have already moved once
today. Any figure typed into help text is a second copy waiting to go stale; pull them from
`CraftingDatabase` / `Character` the way the changelog and `equipment_reference` already do.

## ⚑ THE CRAFTING RECIPE LIST CAN BE ASKED A QUESTION — shipped 2026-09-18

Owner: *"The UI for crafting will likely need redesigned as well once we are done. We want it to be
organized in a way that makes it easy to understand what peoples options are."*

**Measured before redesigning** (`tools/probe/crafting_ui_shape.gd`), because "the crafting UI is
bad" invites fixing whatever the last person noticed:

| skill | recipes | pages @5 | specialist-only |
|---|---|---|---|
| blacksmithing | 68 | **14** | 22 |
| enchanting | 58 | 12 | 25 |
| construction | 52 | 11 | 19 |
| scribing | 48 | 10 | 31 |
| alchemy | 28 | 6 | 12 |

**And a level-1 blacksmith has exactly ONE recipe at their skill** — so they page past 67 rows they
cannot touch to find it. At skill 25 it is still 48 unreachable rows, 9.6 pages of noise. There was
**no filter, no sort and no category**: the only navigation was Prev/Next through everything.

⛑ **So the problem was never that rows were ugly — the list had no way to ask a question.** Four
now exist, as four named buttons (not one cycling button, which makes you press three times to find
out what the options are):

| filter | question |
|---|---|
| **Can Make** *(default)* | what can I act on right now — materials in hand, or commissionable |
| **At My Skill** | what can I attempt, materials aside |
| **Wanted** | what is another player paying for |
| **All** | everything, including what is coming |

The header shows **all four counts at once**, so the player sees where their options are without
visiting each filter, and an empty result **says why and points at the filter that has rows**.

**Measured result — blacksmithing, a skill-25 player: 68 rows → 20, 14 pages → 4.**

⛑ **A SIXTH VACUOUS CHECK, and the most instructive of them.** The first probe passed cleanly while
the filter was reverted to return every recipe — because section 4 projected the improvement from
**recipe data** and section 5 only checked the **buttons existed**. Neither touched the rule. The
predicate now lives in `CraftingDatabase.recipe_matches_filter()` — shared, so the client calls it
and the probe runs it over a realistic payload and counts what comes back. Reverting the rule now
fails.

**✅ AND THE DETAIL SCREEN NOW SAYS WHAT YOU GET.** It explained **how** to craft in real depth —
materials, where each one drops, success odds, quality bands, the boost ladder — and **never once
said what the thing was**. No description, no stats. A player could read every number on that page
and still not know whether the item beat what they were wearing. That is crafting fault #2 exactly:
*"the recipe surface does not tell a player what to make or why."*

It now opens with the description, then:

```
Makes:  attack 118   strength 9     (Lv 40, at Standard)
vs your weapon:  attack +23   defense -4
```

⛑ **Sized by the SAME `curve_sized_base_stats` call the craft itself makes**, so the preview cannot
promise one thing and hand over another — these stats used to be hand-authored constants drifting
against a generated drop curve, which is the fault this whole arc started from. The comparison runs
through `Character.item_stat_bonuses`, the one aggregator, not a mirror.

⛑ **Found while building it: the client carried its OWN copy of the item-level damping curve**
(`_get_effective_item_level_for_display`), with a docstring admitting *"this mirrors the server's"*.
The formula matched — but that is the same shape that produced a design figure **wrong by 50**
earlier the same day, already copied into a second file and quoted as a target. It delegates now,
and the probe fails if a re-derivation comes back.

**✅ THE STATION SPRITES ARE DONE (2026-09-18)** — owner reviewed them on screen and every call
they made was right. The post door, quest board, post centre, market, apothecary and three NPCs
were all replaced; the inn was cut. See "THE POST ART PASS" below.

**Still open in the UI arc:** nothing. Inventory bloat is measured and filed with a trigger.

## ⚑ EVERY CAPABILITY NEEDS A DOOR — swept 2026-09-18, now a standing probe

Owner, after catching that the player-commission half had no UI at all: *"You might want to do a
similar check for other work completed this session to ensure players can actually interact with or
make use of things implemented."*

**`tools/probe/session_capabilities_have_doors.gd`** walks every capability built that day and
asserts a surface exists for each. **This arc has shipped a capability with no door SEVEN times** —
party invite, Duel for Valor, the fight log, the death log, the Bestiary Page, the bestiary reader,
and the player commission. The failure is always invisible server-side: the handler is right, the
data is right, and nothing on screen can reach it.

**One real gap the sweep found:** **safe passage had no indicator anywhere.** Three things grant it
(Scroll of Safe Passage, Scroll of Long Passage, a Builder's Make Camp) and a player could carry 40
quiet steps with no surface saying so — then wonder why encounters stopped, and later why they
started again. Now on the HUD as `🛡 Unnoticed N`, deliberately **outside** the danger branch so it
does not appear from nowhere when you walk out of a safe zone.

Corrected while sweeping: `crafted_by` **is** displayed (client.gd ~20431). An earlier note here
claiming otherwise was wrong.

⛑ **TWO MORE FAKE CHECKS, and the second is a new shape worth naming:**
1. *"a Post Job button exists"* searched for `"craft_post_job"` — which the **handler** also
   contains — so deleting the button passed. **Two checks matching one string are one check.**
2. *"a Rework button exists"* searched for `rework_start`, which also sits on a **"Pick Item"**
   button *inside* the rework flow — a flow only reachable **from the deleted button**. It passed
   while the way in was gone. **A door you can only open from behind is not a door.**

Both now name the entry button's literal form. That is **five vacuous checks in one session**, every
one found by fault injection and none by review — so injection is not optional, it is the step that
tells you whether a check is a check.

## ▶ NEXT SESSION — START HERE

### ▶▶ HANDOFF — written at the END of 2026-10-13. READ THIS FIRST; everything below it is the detail.

**State: v0.9.839 is LIVE (client + server, deployed and hash-verified `e8571297a659ef5f`). Everything is pushed;
nothing is held back unreleased.** First commands of the session: `python tools/backlog_audit.py --quiet`, then
`python tools/probe_run.py --smoke` (15 probes, all green at the end of today).

**SHIPPED TODAY (2026-10-13), in order.**
- v0.9.834: threat-quest dungeon entry, rescue NPCs, map-overwrites-panel fixes, floor loot levels, player-weighted dungeon spawns.
- v0.9.835: danger warning == Area readout wording, initiative/Gathering help, escort flag.
- v0.9.836: log hover above the log window, Home Stones show no level, bulk-salvage refresh, Escape-button confirm,
  card faces match fights (finisher + companion/dungeon strikes), Deck names == battle names, battle log opens with the
  foe's traits, crafting XP shown == granted, upgrade recipe text, Warden speaks with pop-ups off, Stop Watching button,
  legendary/artifact headline.
- v0.9.837: one Scroll of Summoning and one of Finding.
- v0.9.838: party leftovers removed (post-exit gate, Lead/Follow prompt, leadership rotation, dead follower lock) and an
  `[ENCOUNTER]` journal line per finished fight.
- v0.9.839: Title menu shows Valor costs, claim offered only at (0,0), Title help corrected.
- Tooling: `tools/probe_run.py` (its smoke gate runs inside `release.sh`), `death_log_audit.py` current-era cutoff +
  encounter report, one flaky smoke probe fixed.

**THE PLAYTEST SHEET (51 items) - STATUS.**
- DONE: 1 2 3 5 8 10 11 12 13 15 16 17 18 19 20 21 22 23 24 31 32 35 36 37 39 42 43 44 45 46 49.
- PARTLY: **26** (loot-grid + victory-card headline done; drops that bypass the grid - dungeon floors, quest/market/craft
  rewards - not covered; the owner said "normal fights", which IS covered, so probably done). **47** (Jarl Ring list row
  done; no extra guidance at (0,0) beyond the High Seat button). **24** (all four lead/follow leftovers gone; dungeon
  entry/exit, go-back-a-floor, the starter-dungeon escort and invites are STILL leader-gated on purpose - ask the owner if
  they meant those). **6** fixed on the owner's hypothesis, never reproduced live.
- GROUP 6 DONE 2026-10-14 (all seven, each with a probe; see the per-item notes at the group-6 line below): 4 (summary counted lines not hits), 9 (Distract now announced), 14 (runes from the panel), 28 (Heavy Draw / Sacrificial), 34 (tomes), 40 (attack vs spell power on cards), 51 (one hydra in two slots). STILL OPEN from it: item 40's non-unique artifact gear + proc runes vs text; the live Sanctuary's existing duplicate rows (51). NOT STARTED: **Group 10** design asks [7
  salvage confirm/auto-salvage, 29 stat-point auto-apply, 30 late minigames too long, 50 gold/gems] need owner decisions.
  **Item 11** (variety: quest boards, monster stat rolls, companion variety, tank mobs) is design-first. **Item 12**
  (3-hourly restarts / events) is an idea only.

**OWNER DIRECTIONS TO CARRY:** empowered monsters "may need reduced slightly" (BALANCE BATCH - size it from the
`[ENCOUNTER]` data first, not by guessing); dungeon spawns weighted toward players (done); balance work is BATCHED -
run the calibration chain ONCE after the batch, never per item; release only when the owner asks.

**(SUPERSEDED 2026-10-15 - see "START HERE - PLAN" at the top of this file.) WHAT TO DO FIRST TOMORROW, in order:**
1. **Read the new data.** `python tools/death_log_audit.py` now ends with an ENCOUNTERS table (deaths per encounter by
   role / level band / level gap / modifier) from the `[ENCOUNTER]` lines that began with v0.9.838. It will be thin after
   one day - report n, do not conclude. It is the input the empowered-difficulty decision needs.
2. **Group 6, verify-then-fix** (seven small measurements). Start with 34 (Tome of Gambit not in the deck - a real bug
   if true) and 51 (duplicate companion slots - an exploit if true).
3. **Ask the owner** about group 10, the remaining leader gates (item 24) and item 47's turn-in guidance.
4. **Then the BALANCE BATCH** (item 9) once the owner is ready: empowered difficulty, the L6+ reference-player scaling
   (live base CON 17-19 vs sim 12-13; live gear hp_bonus ~3x the sim's), Fighter mitigation, the rest. Run `-- preflight`
   FIRST, then speciescal -> refcal -> rolecal ONCE each.

**(SUPERSEDED 2026-10-15: v0.9.844 is live - see "START HERE - PLAN" at the top.) STATE 2026-10-14 END OF DAY: v0.9.841 is LIVE (see the RELEASED note in item 9). Start with the chain re-run decision (item 9), then item 14 S0.** **NEW VISION 2026-10-14 (item 14 below): strategic party combat through companions** - roles, a tactics focus, up to 5 companions (4 in the column, 1 beside you). Design-first; recommended order is release the current batch -> run the item 9 chain on it -> start item 14's S0 (no code). Read item 14 before proposing companion work.

**THINGS I GOT WRONG TODAY - do not repeat them.**
- (a) The audit's early-game finding was OLD-BUILD data: 46 of 63 "current" deaths predate the 09-19 curve refit (monsters
  at 2.4-19x today's HP). The cutoff is now 2026-09-20 (`--since` overrides). Always divide a death's recorded
  `monster_max_hp` by today's spawn HP before trusting a death count.
- (b) "L1-2 kit too rich" came from a 20-death sample with a heavy tail and was reversed on re-measure.
- (c) `z_index` is capped at 4096 and a `top_level` node's z is ABSOLUTE (that is why the log hover sat behind the log).
- (d) In this shell, backslash-n inside Python heredocs can arrive as a REAL newline: build escapes with `chr(92)` and read
  the diff of any edit to a one-line GDScript string. `docs/BACKLOG.md` has CRLF line endings in the working tree (git
  normalises to LF) - anchor on text, not on trailing "\n".

**STILL OPEN, UNCHANGED:** Player Phantoms (built, held behind `PHANTOM_POSTS_ENABLED := false`; the client surfaces are the
remaining task - see the block below); `probe_run.py --repeat N`; move measurement scripts out of `tools/probe/`; triage
the 10 script-error probes.


### ⚑ OWNER PLAYTEST SHEET — 51 items, received 2026-10-13 (Google Sheet, "anyone with link")

Takes priority over the Player Phantoms client block below (owner: "start there"). Items are
grouped by SHARED CAUSE, in the order their inputs settle. Tick each here as it lands. Sheet item
numbers are in brackets. **None of the groups below were verified against code when written** —
the grouping is from reading the sheet; confirm the cause before fixing.

5. - [x] **ALL TEN DONE 2026-10-13 (v0.9.836-839) - TEXT/NUMBERS THAT DISAGREE** [15 Companion card face vs log; 16 Double Cross face vs
      actual; 18 potion HP in combat list; 39 card name differs Deck vs battle (Sorcerer Wild
      Strike/Blast); 17 log hover renders behind the log; 19 monster traits (Elite/Champion/Swift)
      missing from combat log; 44 can't inspect Tome of Fortify; 49 Title help inaccurate;
      32 Hybrid Catalyst "unknown effect"; 43 crafting XP shown vs granted].
      - [x] **[15] DONE IN CODE 2026-10-13 (SERVER; needs a deploy) - companion/dungeon card faces.**
        I could not reproduce a WRONG number: these cards had NO number at all (the server deliberately
        omitted them from the card quotes and the client's third row was blank for them), so there was
        nothing on the face to compare with the log. The owner's complaint is read as that gap. Strike-kind
        cards (14 kinds) are now quoted through `_companion_strike_mod` - the same function the cast uses,
        split out of `_companion_strike` - via `COMPANION_STRIKE_POWER` (kind -> power, mirroring the call
        sites). Probe `companion_card_face_matches_the_cast.gd` casts every kind at L20 and L200: worst 4% off
        (variance), and 61% off when a power in the table is changed. **Not done:** non-damage kinds (guard,
        rage, heal, shield, focus) still show the shared description only; the table duplicates the call-site
        powers (the probe is the guard - fold the call sites onto the table when next in there).
      - [ ] **[17] NOT STARTED - needs a screenshot, deliberately.** Read the code only: the live battle
        log (`_battle_log_band`) hovers through `_formula_popup` (z 400, parented to the window root, so
        above the combat scene's z 100-200 layers); the [L] fight-log window (`fight_log_panel.gd`, z 4000)
        draws its OWN `LogDetail` box (z 400 inside it = 4400) since 2026-09-18. By the code both are in
        front, so a guess here would be the third wrong theory. Ask the owner WHICH log (live band / [L]
        window / death replay) and for a shot, or reproduce via `tools/test_setup/shots.py` with a hover
        injected; check `_formula_popup` against the death-replay path first (it draws the combat panel's
        popup while a z 4000 panel is up).
      - [x] **SMOKE-GATE FLAKE FIXED 2026-10-13 (found on the v0.9.837 release):** `world_dungeon_roll_is_uniform`
        failed ~1 run in 10 - unseeded, and its 0.95x centre-density bound sat 1.35 sd from the mean of ~700 rolls.
        Seeded, bound moved to 0.85x (~4 sd). The v0.9.837 release gate passed regardless. A flaky smoke probe
        either blocks a good release or trains people to rerun until green; the same check applies to any other
        sampled probe in `--smoke` (not audited).
      - [x] **[49] DONE IN CODE 2026-10-13 (client + server; needs a release) - Title menu / help audited claim by
        claim against `titles.gd` and the claim/forge handlers.** Found and fixed: (1) **the Title menu never
        showed a Valor cost** - it read `gold_cost` keys that the tables dropped when title abilities moved to
        valor (the help page had been fixed for the same drift on 2026-09-11, this menu was missed), so players
        learned prices by being refused; (2) the menu offered a claim **within one tile** of the seat while the
        claim requires exactly (0,0); (3) the help did not say a High King **usurps** the sitting one, that a
        Jarl needs no High King on the throne, or that the forge is `Fire Mt` THEN `Forge`. One helper,
        `_title_ability_cost_parts`, now feeds both the menu and the help line. Probe
        `title_menu_tells_the_truth.gd` (15 abilities audited). Verified correct and left alone: levels 50-500 /
        200-1000, ring 0.5% from Lv50+, crown 0.2% from Lv200+, abuse thresholds 8 / 15, Elder auto-grant at 1000.
        Still unverified by the owner: whether this was the line they meant.
      - [x] **[43] DONE IN CODE 2026-10-13 (SERVER; needs a deploy) - crafting XP shown vs granted.**
        Cause: the craft result reported the amount OFFERED; `add_experience` then multiplies (race x
        Sanctuary x Mentee) and `add_job_xp` adds the committed-job +50%, so a committed crafter saw 20 and got
        30. Both now return what they granted (`xp_gained`, `xp_granted`) and both craft sites in
        `_finalize_craft` report that. Probe `shown_xp_is_granted_xp.gd`. **Not done:** gathering results
        (`gathering_complete`, scratch-off) have the same shape and still report offered amounts; party members
        are still offered the pre-bonus amount (deliberate - their own bonus applies). Not fault-injected.
      - [x] **[39] DONE IN CODE 2026-10-13 (SERVER; needs a deploy) - Deck names vs battle names.**
        Cause: the Deck panel renders `ability_data.*[].display`, which `Character.get_all_available_abilities`
        fills from ONE string per card id (the archetype's - a Sorcerer's `blast` is "Blast"); battle names a
        card through `CombatManager.display_name_for` ("Wild Surge" for a Sorcerer; the owner wrote "Wild
        Strike"). New `server._class_named_abilities` rewrites `display` on a copy from the combat table for
        every card the class renames, in `handle_get_abilities`. Probe `deck_names_match_battle_names.gd`: 9
        classes, 50 class-renamed cards, deck name == battle name; red (6 of 50) with the helper disabled.
        **Not swept:** other surfaces that name a card from client-side tables (`client.gd` ~2848 / ~16812,
        the equip prompts) - the probe covers only what the server sends the Deck. Next time a card name is
        reported, run `-- cardnames` and compare every surface rather than this one.
      - [x] **[19] DONE IN CODE 2026-10-13 (client + shared; next client release) - the battle log opens
        with WHO you are fighting.** Traits were on the encounter text, the nameplate and Analyze, but the
        live log began at the first blow. `CombatManager.fight_log_header` builds one line (name, level,
        Elite / Apex species / Rare variant, each empowered modifier as a hover chip, every non-loot
        trait) from the same tables the encounter text reads; the client appends it after the scene is
        populated. Probe `fight_log_names_the_foe.gd` (content + exactly-one client statement; goes red with
        the client line commented out). **Not verified by eye:** I have not looked at it rendered - the
        header's wrap/width in the log panel wants a screenshot with item 17. **Not changed:** the death
        record (`death_snapshot`) still stores no traits; `cause_of_death` is the only monster identity there.
      - [x] **[16] DONE IN CODE 2026-10-13 (SERVER, `combat_manager.gd`; needs a server deploy) - the
        Trickster finisher's face vs the real hit.** One card (`perfect_heist`: Grifter Double Cross, Ranger
        Killing Shot, Ninja Assassinate). `card_face_truth` could not see it: it only checks quotes of kind
        "damage" and silently skips the rest. Measured on real casts, crits excluded: the face under-quoted by
        up to ~2x for two reasons. (1) It left out the damage-bonus + live-buff pipeline every other card's
        quote carries (`apply_skill_damage_bonus`, damage buff, analyze bonus, damage penalty). (2) It sized
        the strike on the stacks BANKED, but every Trickster cast feeds the engine +1 BEFORE it resolves -
        new `_finisher_stacks()` is used by the damage quote, the value quote, and the Ninja's kill chance
        (which was quoting 2/8/14/23% against a real 5/11/17/26%). Probe
        `finisher_quote_matches_the_cast.gd`: 3 classes x L20/L200 x engine 0/2/4/7, median dealt/quote per
        cell within 20% (worst 8%), plus the kill chance against 220 real casts per engine level. The damage
        half goes red with the +1 removed (worst 60% off). Not fault-injected: the kill-chance half.
        Limit: each cell's median is over non-crit, non-execute casts only.
      - [x] **[18] DONE IN CODE 2026-10-13 (client; next client release) - the combat Use Item list's
        potion amounts.** Measured, not guessed: on a geared level-40 character the list said **+155 HP** for
        a potion that healed **+381** (2.5x off), and **every resource potion showed no amount at all**.
        Two causes in `_combat_item_gain_line`: it measured the percentage part against the BASE `max_hp`
        while the server heals against `get_total_max_hp()` (gear + CON x5 + house bonus) - so the
        docstring's promise that the number shown is the number granted was only true with nothing equipped
        - and it read `max_resource` / `resource_name`, keys the server never sends. Now it uses
        `total_max_hp` and the class's primary resource against its `total_max_*` pool, the same pools the
        server's use handler reads. Probe `combat_item_list_shows_what_you_get.gd`: 9 classes x 4 levels x 4
        potions (144 cases) with geared characters; goes red if the base-HP pool returns. **Not covered:** a
        companion-target heal (no such potion exists in the data; the server chooses the target at use).
      - [x] **[32] + [44] DONE IN CODE 2026-10-13 (client; next client release) - items that said nothing
        about themselves.** Method: inspect EVERY item type the loot tables can produce (112, read from
        `drop_tables.gd`'s own constants so a new one is covered automatically). **Seven** had no real
        description: **Hybrid Catalyst and Ascension Catalyst** ("Unknown effect" - the owner's [32]),
        **three Bane potions** ("Unknown effect"), the **material pouch** ("Unknown effect"), and **every
        card tome** (the generic "Tome of knowledge - permanent enhancement" - the owner's [44]). Each now
        says what it does, read off the code that does it: the catalysts name their fusion and its rules
        (Hybrid: two DIFFERENT monster types, both rank 5+; Ascension: three of the same type and tier ->
        one tier higher at rank 1); bane potions read `POTION_EFFECTS` ("+50% damage against Dragon
        monsters for your next 3 battles"); the pouch says it gives level-matched ore; a card tome says
        "PERMANENT: -15% Berserk cost. Applies to every copy of that card you own", naming the card as it
        is called in your hand. **Not reproduced:** "can't inspect" - the pick-an-item route works for a
        tome; the real defect was the useless text. **A wrong turn, retracted:** I briefly believed card
        tomes could not be USED at all (a grep for `card_tome` found no consumer); they can - the consumer
        keys on `card_kind` (`drop_tables.gd` effect + the server's "You study the ..." message). Probe
        `every_item_says_what_it_does.gd` (all 112 types; goes red if a description is removed).
      - [x] **[3b] DONE IN CODE 2026-10-13 (client; ships in the next client release) - Inspect now lists
        everything the card preview does.** CORRECTION to my earlier note here: the "+2 all ability
        ranks" I thought Inspect dropped was a GM-tool key (`ability_rank_all`) that nothing reads, not a
        real affix - that evidence was wrong. The REAL fault, measured on real generated gear: **90 of
        227 epic-and-up items** showed stats on the inventory card that Inspect never mentioned (card cost
        and power bonuses, crit chance/damage, extra-turn chance, mana/stamina/energy on hit, HP on kill)
        because the card's tokens (`_format_chase_affix_tokens`, v0.9.608) had no counterpart on the
        page. Fixed with ONE table, `_chase_affix_rows` (each row = short token + full-word line); the
        card reads the tokens, and `_display_computed_item_bonuses` - the one builder shared by the
        Inspect page, the shop item page AND the equip comparison - prints the lines under "Special
        effects". Card gear names the CARD as it is called in your hand (`_ability_display_name`).
        Preview-only numbers: 90 -> 0. Probe `inspect_shows_what_the_card_shows.gd` (hand-built item with
        all ten chase keys + 192 generated items; goes red if the block is removed).
7. - [ ] **SMALL FIXES** [(12 DONE 2026-10-13, client: the dungeon Escape button now opens a "Leave the
      dungeon?" confirmation; probe `escape_button_asks_first.gd`); (22 DONE 2026-10-13, SERVER: `_send_hint` takes a `fallback` and says it as plain guide text when pop-ups are off; the Warden's welcome / walk-to-the-door / weapon lines carry one; probe `warden_speaks_with_popups_off.gd`, source-level only - not played through; the other ~25 teaching hints stay silent when off, by design); 22-was: disabling Help Pop-ups breaks
      the tutorial; 31 Home Stones shouldn't have levels (DONE 2026-10-13 after the owner named the surfaces - inventory and market: `DropTables.shows_item_level`, asked at the 2 item-card and 3 market sites; probe `home_stone_shows_no_level.gd`; the old list-view text sites in client.gd were not touched. Earlier note: the item generator gives every Home Stone a `level` and nothing I found reads it for the effect, but item levels print at 5+ client sites - lines ~11221, 20659, 22147, 50606 - and the owner did not say WHICH surface; needs the screen or a decision: drop `level` at generation + suppress the Lv suffix for `home_stone_*` in one shared formatter); 6 inventory not refreshing after salvage;
      20 no way to stop watching a player (DONE 2026-10-13, client: slot 0 is a visible Stop Watching button while watching; probe `watching_has_a_stop_button.gd`, source-level, not clicked through); 13 what does Blacksmith Armor Upgrade do (DONE 2026-10-13, SERVER: the recipe text now says it raises the equipped item's LEVEL, the Poor/Fine/Masterwork multipliers, and both caps - read off the craft code; probe `upgrade_recipes_say_what_they_do.gd`); 45 why several summoning/finding scrolls (DONE 2026-10-13 per the owner's "merge into one each": there were two families with identical effects - loot "Scroll of Summoning/Finding" (with Ancient/Arcane prefixes that changed nothing) and scribed "Scroll of Monster Select/Target Farm". One name each at every rarity; probe `one_summoning_one_finding.gd`; shared change, needs a client+server release; existing saved scrolls keep their stored names until re-made); 26 legendary/artifact drops not announced in victory feed (PARTLY DONE 2026-10-13, client: the loot minigame never celebrated the ARTIFACT rarity - only rare/epic/legendary - and the victory card now opens with a coloured "LEGENDARY/ARTIFACT FOUND: name" line; probe `top_rarity_drops_are_announced.gd`, source-level, not seen on screen. NOT covered: drops that bypass the loot grid - dungeon floor pickups, quest/market/craft rewards - the owner did not say which source);
      47 Jarl ring still equippable + no turn-in guidance at 0,0 (PARTLY DONE 2026-10-13, client: the list row now says "Quest item - turn in at The High Seat (0,0)" instead of an Atk bonus; probe `title_items_are_not_gear_in_the_list.gd`. Equip was already refused server-side and has no menu entry. NOT done: guidance when standing at 0,0 beyond the existing High Seat button - needs a look at the screen); 6 salvage refresh (FIXED 2026-10-13 on the owner's hypothesis, client: the bulk-salvage result state skipped display_inventory on purpose and so never gave a still-visible inventory panel the new list - it now calls `inventory_panel.populate`; read from code, not reproduced live; probe covers the statement only); 17 (DONE 2026-10-13 - the owner named the L / death-screen log window: its hover box is top_level at z 400, which is ABSOLUTE, under the window's 4000; now 4096, the engine maximum; probe `log_hover_is_above_the_log.gd` red before, green after)].
8. - [ ] **PARTY PLAY** - (RELEASED v0.9.833-844; still needs a two-human PLAYTEST - Wave 0) sheet item 24, MOSTLY DONE 2026-10-13 (server + client; needs a release; NOT
      playtested). The join-a-fight half had already shipped in v0.9.833 (map marker, run-in join). What
      was still wrong was four leftovers of the old lead/follow model, which is why players "could not
      properly leave the posts": (1) a post-EXIT gate - only the leader could walk out, and only once
      everyone stood beside them ("must be beside you before the party leaves the post"); (2) the
      Lead/Follow question when a party forms; (3) leadership rotating after every fight and every
      gather (+ the Lead: Rotate/Fixed toggle); (4) `_party_follower_locked` / `_party_follower_denied`,
      defined and called by nothing. All removed; the inviter leads and nothing rotates. The party help
      paragraph (which still said "the leader moves, the others follow") is rewritten from the real
      rules. Probe `party_has_no_leader_follower_remnants.gd` (8 statement checks, all red on the old
      code); `the_party_fights_together` and the six other party probes still pass.
      **Still leader-gated, deliberately left:** dungeon ENTRY/EXIT (the leader takes the party in and out
      - one instance, one door), "go back a floor" ("Your party leader controls dungeon navigation"), the
      starter-dungeon Warden escort, and invites. If the owner meant any of those too, say which.
      **Dead data left in place:** `rotation_order` / `rotation_idx` / `control_mode` keys on the party
      dict and `handle_party_set_control_mode`, kept so an old client's toggle does not error.
9. - [ ] **BALANCE BATCH — wait for the chain, do not fix one by one.**
      **OWNER DECISION 2026-10-14 on the candidate curve: SHIP ONLY IF death risk does not get progressively worse; players fighting near their level with semi-appropriate gear must not be punished; otherwise add power back (gold sinks, companions). Measured: it WOULD worsen average-geared death risk at L100/L500 (3.7->11.1, 7.4->14.8; n=27 per cell so noisy, but monotone) - so the candidate is HELD.** The owner's diagnosis, confirmed by the data: deaths come from TRAIT-STACKED monsters and BIG LEVEL GAPS, not plain same-level fights (11 of 13 current-era deaths were modified monsters). **LEVER 1 - BUILT, UNRELEASED: the OPENING-TURN CAP** (`combat_manager._apply_opening_burst_cap`, constants `OPENING_TURN_CAP_PCT` 0.75, `PROTECTED_GAP_MIN` 15, `PROTECTED_GAP_FRACTION` 0.25, `PROTECTED_MIN_REF_HP` 0.5). In a PROTECTED fight the monster's FIRST turn (first strike / ambush / drain) cannot take more than 75% of max HP, so the player always gets to act. Protected = monster <= max(15, 25% of your level) above you AND max HP >= half the reference player's AND you walked in with >= half your bar. A blatant over-reacher (monster 2x your level, or a L80 with 103 HP against a reference of 1,178) is NOT protected and can still die in round one - owner's wording: *'only if the player is blatantly pushing way past what they should be fighting'*. Probe `opening_blow_cannot_kill_a_healthy_player` (old code killed a healthy L91 in 16 of 40 trials, the cap 0 of 40; over-reachers still die 22 of 40). **Replaying the 13 real current-era deaths through the rule: 6 (46%) were protected fights that ended on the monster's first turn - they would have had an action.** (Caveat: n=13, and most are the owner's own test characters.) `riskcurve` cannot show the cap's effect (27 effective samples per cell, single cells swing 11-15 points between runs) - do not read it as evidence either way. **LEVER 2 - DECIDED BY THE OWNER 2026-10-14 AND BUILT (unreleased): (a) the band is now +/-5% of the area's level (was +/-10%), STILL A PERCENTAGE - the owner rejected a flat 5-level cap because *'5 levels later doesn't mean as much at later levels'* - with the existing 1-level floor; that is +/-4 at L91 and +/-25 at L500 (was +/-9 and +/-50). One constant, `world_system.AREA_LEVEL_BAND_PCT`, read by spawns, the area readout and the danger warning. Probe `area_level_band_is_five_percent` (old code: 27 of 35 spots out of range). (b) PLAYER POSTS + PHANTOMS stays the LONG answer (owner agreed): a place to farm appropriate-level content that does not depend on the world's level geometry - built, held behind `PHANTOM_POSTS_ENABLED := false`, client surfaces still to do. Original options text follows.** **LEVER 2 - OWNER TO CHOOSE: the level band.** `get_monster_level_range` spreads monsters +/-10% of the local level (+/-9 at L91, +/-50 at L500) and hotspots multiply the level 1.5-2.5x, so 'around your level' stops existing far from the centre (owner could not find farmable ground on a L91 character). Options: (a) cap the band, e.g. +/-10% but never more than ~5 levels - a one-line change, the cheap answer; (b) the owner's alternative: progress PLAYER POSTS AND PHANTOMS (built, held behind `PHANTOM_POSTS_ENABLED := false`, client surfaces still to do) as the place to farm appropriate-level content. Not mutually exclusive: (a) now, (b) as the long answer. **THEN:** re-run the chain with the cap in, Temper/gold in the player model, and the companion arc (item 14) in view - judge the candidate again against 'death risk must FALL with progression'. The candidate curve itself: `docs/balance/data/candidate_reference_monster_curve_2026-10-14.json`.
      **ITEM 9 SESSION 2026-10-14 (after v0.9.841) - THREE FINDINGS.** (1) **LIVE DATA CANNOT DRIVE THIS BATCH.** The `[ENCOUNTER]` line is live but 0 fights have logged: the server saw ~5 accounts in 25 days (Dextobust33 16 logins, p3smerga 4, Caps 3, Xinthor 2, QSmackGalaxy 1) and 6 logins in the last 9 days; the 13 current-era deaths are mostly the owner's own test characters. So 'wait for the live data' is no longer a plan - evidence is the simulator plus the owner's play, judged against the DESIGN TARGETS. (2) **INSTRUMENT DEFECT, FIXED: `riskcurve` printed '216 fights per cell' but ran 27** (`int(24/9)+1 = 3` per class), so every rate moved in 3.7-point steps and a cell swung 11-15 points between identical runs. Every death-rate comparison made before this fix had ~1/10 of the claimed power. It now runs 30 per class (270 per cell, one death = 0.37 pt, ~85 s) and prints the true count. (3) **WITH REAL n, THE CANDIDATE CURVE STILL FAILS THE OWNER'S CONDITION AT HIGH LEVEL.** Death % per fight, shipped -> candidate, both with the opening-turn cap: average gear L10 1.9->3.3, L30 1.9->3.0, L100 8.1->7.0 (no worse), **L500 5.2->11.9**; under-geared L100 5.9->8.9, **L500 5.6->13.7**; best gear <=1pt change everywhere. So the candidate's tougher plain fights do NOT raise death risk through L100, but double it at L500 for average/under-geared players. **ALSO TRUE OF THE SHIPPED GAME:** average-gear death risk is 0.4, 1.9, 1.9, **8.1**, 5.2 at L3/10/30/100/500 - it HUMPS at L100 (1 in 12 plain fights) instead of falling with progression, which is the owner's lived experience on a L91 character. That hump, not the candidate, is the thing to understand first. **NEXT (not done):** run the read-only audits (`-- forensics`, `-- roles`, `-- spread`) at L100 average gear to find WHAT kills there (role, species, trait), then decide between (a) shipping the candidate for L<=250 only (needs a consistency check - role_multipliers/species_power were solved against the full candidate base, so a hand-blend is a patch, not a calibration), (b) a fresh chain run after the L100 hump is understood. Numbers: `the two riskcurve logs are in docs/balance/data/riskcurve_270_*; a re-run is 85 s.
      **EMPOWERED-0.58 EXPERIMENT 2026-10-14 - RESULT: DOES NOT MEET THE OWNER'S CONDITION; NOT SHIPPED.** Candidate base curve + empowered win target 0.50->0.58, `rolecal --budget=5400` (56 min) then 270-fight `riskcurve`. Death % per fight, shipped -> candidate (0.50) -> candidate2 (0.58): average gear L100 8.1 -> 7.0 -> **5.9** (better than shipped), L500 5.2 -> 11.9 -> **11.1** (still 2x shipped); under-geared L100 5.9 -> 8.9 -> **10.4**, L500 5.6 -> 13.7 -> **15.2** (worse); bis L100 1.5, L500 5.6. So easing empowered fixes the L100 hump but NOT the L500 doubling - the cause there is the candidate's tougher PLAIN base, not the role layer. rolecal also left boss L1/L10/L10000 SATURATED (clamped 12/12) and elite L1/L10 SATURATED, so the role layer cannot reach its targets on the candidate base. Files: `docs/balance/data/candidate2_empowered058_curve_2026-10-14.json`, `riskcurve_270_candidate2_empowered058.txt`. Working tree restored to shipped values. **DECISION NEEDED (owner):** (a) keep the shipped curve and ship ONLY an empowered easing on it (needs its own rolecal + riskcurve, ~1h, gets L100 average 8.1 toward ~6) or (b) shelve the candidate base until companions/gold add player power (item 14), then re-run the chain.
      **OPTION A RESULT 2026-10-15 (shipped base + empowered win 0.58, rolecal 53 min + riskcurve): FAILS, NOT SHIPPED.** Death % per fight, shipped -> A: average L100 8.1 -> **10.0**, L500 5.2 -> 4.8; under-geared L100 5.9 -> **9.6**, L500 5.6 -> **9.3**; bis L100 1.5 -> 4.1. Noise is ~+/-1.7 pts, so average L100/L500 are a wash, but under-geared worsens beyond noise at both. Easing empowered does NOT lower death risk for under-geared players on either base - the first run's L100 average gain (5.9) was noise or base-specific. The role layer also saturates at elite L1/L10 and boss L1/L10000. CONCLUSION: empowered's win target is not the lever; stop tuning it. Remaining honest route: player power (item 14 companions, gold sinks) then re-run the chain. Files: `docs/balance/data/shipped_base_empowered058_curve_2026-10-15.json`, `riskcurve_270_shipped_base_empowered058.txt`.
      **RELEASED 2026-10-14 as v0.9.841 (client + server, hash-verified): the opening-turn cap and the +/-5% level band, with changelog + help. v0.9.840 (same day) carried gold, auto-spend, the salvage toggle, Temper, the reference-player stats fix and the group-6 fixes. The held monster curve (candidate in `docs/balance/data/`) is NOT live - re-run the chain with the cap, the band and Temper in view before deciding.**
      **CHAIN RUN 2026-10-14 (after the reference-player stats fix; v0.9.840 live) - RESULT NOT SHIPPED, awaiting the owner.** preflight passed; speciescal 11.7 min, refcal 10.8, rolecal 44 (budget 45 - near the limit). The candidate curve is saved at `docs/balance/data/candidate_reference_monster_curve_2026-10-14.json` (apply with `cp` over `shared/reference_monster_curve.json`, then a release + server deploy); the working file is the SHIPPED curve. Monster HP x1.2-1.7 and strength x1.4-1.85 at L25-L1000; species_power pinned at the 2.5 ceiling fell 12 -> 5. **Independent read (`refval`, fresh process, corrected player), HP cost per normal fight vs the 40% target:** old curve 22-27% at L50-L1000 (players were getting about HALF the intended challenge); candidate 35-43% at L100-L1000 (on target). **NOT FIXED BY EITHER CURVE:** L1-L50 is very easy (89-100% win, 11-23% cost) and the high end rings (L2500 48% cost / 64% win, L5000 26% cost / 87% win, L10000 49% cost / 64% win) - a per-level anchor problem, not something a second pass fixes (ONE PASS EACH; needing to iterate means two layers fight). `rolecal`: boss L10 SATURATED (clamped 12/12, so not converged), boss L50 38% vs 30%, elite L1 50% vs 40%. Preflight [2]: L250 sampler vs fight loop 8pp apart (noise ~5pp). Numbers: `docs/balance/data/refval_old_curve_vs_candidate_2026-10-14.txt`. 
      **READ FIRST (2026-10-14): `docs/balance/rank1_sorcerer_death_2026-10-06.md`** - the owner's L91 rank-1 Sorcerer died in ONE round (6,060 dmg vs 2,242 HP), and comparing his record with the simulator found the reference player had ~HALF a real player's stats (`level_up()` truncated fractional gains and granted no stat points; fixed, probe `level_up_paths_agree`). **The previous curve was calibrated against that weaker character - run the chain on the corrected player and judge against absolute targets, not the old numbers.** Also asks: does admin use explain his gear/pace (owner), and measure the first-strike + ambush + drain burst tail.
      ▶ **OWNER DIRECTION 2026-10-13: empowered-monster difficulty "may need reduced slightly"** - goes in this BALANCE BATCH
      (the sim agrees empowered is the main source of non-wins: ~66-69% win at L1-10 vs a 55% target), to be set when the
      batch runs; wait for the [ENCOUNTER] data first so the size of the change is measured, not guessed.
      ▶ **EARLY-DEATH INVESTIGATION, 2026-10-13 - THE "EARLY GAME IS TOO HARD" FINDING WAS STALE DATA.
      READ THIS BEFORE THE TWO BLOCKS BELOW IT, WHICH IT CORRECTS.**
        * **What was wrong:** `death_log_audit.py` counted every death since 2026-09-05 as "current". Dividing each
          death's recorded `monster_max_hp` by what the game spawns for that species and level TODAY (Wolf Lv2
          = 94 HP): deaths on 09-04..09-06 faced **10-19x** today's HP, 09-08..09-15 faced **2.4-6x**, and from
          09-19 on the ratio is ~1. So 46 of the "63 current deaths" - 28 of them at L1-5 - happened against
          monsters the game no longer spawns. The "68% of deaths at L1-9", "Tricksters 54%", "median 3 rounds"
          and "21% lost a bar in 2 rounds" figures I wrote up earlier all describe the OLD builds. **Since the
          refit shipped (2026-09-19) there have been 2 deaths at L5 or below in four weeks.**
        * **Fixed the instrument:** `CUTOFF` is now 2026-09-20 (with the reasoning in the file) and
          `--since YYYY-MM-DD` overrides it. It reports "13 since 2026-09-20, 84 before it (older builds)".
        * **The CURRENT era, n=13 (small - treat as a lead, not a fit):** by level 1-9: 3, 10-24: 7, 25-49: 2,
          50-99: 1 - i.e. deaths are now mostly L10-24 and do NOT fall with level yet. **11 of 13 were killed by
          a monster carrying a modifier** (Vampiric, Juggernaut, Warded, Venomous, Thorned, Broodcalling, Gilded,
          Shield Guardian, or a Champion/Cunning-Prey elite); only a Wraith (Lv37 vs a L13 player) and an Ogre
          were plain. 8 of 13 died within 2 rounds, 5 lost a full bar in <= 2; **none walked in hurt** (0 of 13
          below 70% HP), so these are single-encounter kills, not attrition. 5 of 13 were at parity, 3 were
          "far above" (11+ levels over the player, e.g. Titan Champion Lv60 vs L35, Wraith Lv37 vs L13) - the
          danger-step guard (v0.9.835, 2026-10-13) postdates all of them.
        * **The simulator agrees about WHERE the risk is** (`-- roles`, win%): normal 100% at L1-10, **empowered
          66-69%, elite 64-79%, boss 74%** at L1-10 (targets 55 / 65 / 80). Empowered spawn on ~15% of Lv5+
          monsters, so the sim already predicts that almost all non-wins come from modified monsters, and live
          deaths say the same (11 of 13). **This is the one concrete lead:** whether a ~1-in-3 loss against ANY
          empowered monster at L1-10 is the intended price (the BALANCE doc says most die by design but the risk
          must FALL with progression) is a DESIGN decision, and it lines up with backlog item 11d ("tank mobs
          crazy stronger", suspect `species_power`).
        * **Not measured, and needed before any change:** deaths PER ENCOUNTER by modifier (the log has deaths,
          not encounters), so "modified monsters kill 85%" cannot yet be separated from "they are 15-25% of
          what players meet". Needs an encounter counter in the server log (e.g. one `[ENCOUNTER]` line with
          role/mods/level gap and outcome) - cheap, and it would also give the real 1.81%-style rate that
          `death_log_audit` cannot compute today.
        * **BUILT 2026-10-13 (server; needs a deploy - ships as the next release):** every finished fight prints
          `[ENCOUNTER] outcome= role= mods= variant= mon= mlvl= mhp= class= plvl= gap= rounds= hp0= hp1= hpmax=
          party= dead= first= dungeon=` (`CombatManager.encounter_log_line`, called from `end_combat` and
          `_end_party_combat` before they erase the combat). `outcome` is derived: won / died (not a win at 0 HP)
          / left (fled, retreated or aborted). No player name. `death_log_audit.py` now ends with an ENCOUNTERS
          section - deaths per encounter by role, level band, level gap and modifier - read from
          `journalctl`; `--no-encounters` skips it. Probe `encounter_line_is_logged.gd` (12 checks); verified by
          ending two real fights through the engine. **No data exists until it is deployed and played.**
          Caveats: a flock chain logs one line per monster; "left" mixes flee, retreat and disconnect; a party
          fight is one line carrying the LEADER's class/level; the journal's retention bounds the sample.
        * **The reference-player result below still stands as a statement about L6+ scaling, but its
          motivation ("explain the early deaths") is gone:** the early deaths it was meant to explain were an
          old-build artefact. L6+ remains a real but lower-priority fidelity gap.
      ▶ **LIVE-DATA CHECK RUN 2026-10-13 (steps 1-2; step 3, reference player vs live saves, NOT yet run).**
      `death_log_audit.py`: 97 deaths recorded, **63 since the 2026-09-05 balance pass**. By level band:
      1-9 = 43 (68%), 10-24 = 17, 25-49 = 2, 50-99 = 1. By class: **Grifter 13, Ranger 11, Ninja 10 = 34 of
      63 (54%) are Tricksters**, then Wizard 9, Paladin 5, Sorcerer 4, Barbarian 4, Fighter 3, Sage 3, Thief
      1. Of 49 deaths naming the monster's level, 32 were at or below the player's level (gap <= 2) - i.e.
      the curve, not over-reaching. **Median 3 rounds; 50% died in 2 rounds or fewer; 21% took a full bar
      in <= 2 rounds** ("I never got to play"). 24% walked in below 70% HP. Top killers: Wolf 7, Giant Rat 4,
      Goblin 4, Skeleton 3. 7 deaths record no fight at all (excluded). `check_player_progress.sh`: current-era
      characters reached L91 (Dexto, Sorcerer), L57 (Fighter), L22 (Paladin), then L12 and below; so
      high-level balance now has a little real data (3 characters past L20) and the lootsim extrapolation
      can be checked against L57-L91. **What it says, and does not:** the early game (L1-2) is where players
      die and Tricksters die most - consistent with the existing per-class items below, NOT a reason to
      touch anything before the chain. It is a count of deaths, not a rate: the population denominator
      (encounters per class) is not in this output, so "Tricksters die most" may partly be "most people
      play Tricksters" - count BOTH sides before acting (memory `feedback_count_both_sides_of_the_ratio`).
      ▶ **CORRECTION, SAME DAY - STEP (1) BELOW DID NOT SURVIVE ITS OWN RE-MEASURE. NOT EDITED.** The note
      said to re-measure on the population the fit used before touching the L1-2 kit. Doing that:
        * **The L1-2 HP gap is not a "kit too rich" finding.** Sim and live draw items from the same generator.
          Per ITEM, the sim gives an HP affix to 16% of items (mean +27) at BOTH L1-2 and L3-5; live gives 6%
          (6 of 99) at L1-2 and 20% (22 of 109) at L3-5, mean +25 / +31. Pooled over L1-5 live is 13.5% vs the
          sim's 16% - consistent. L1-2 alone is 2.7 sd low (~p 0.4% unadjusted, ~2% after allowing for four
          bands), so it may be real or luck; HP has a heavy tail (live L1-4 `hp_bonus`: mean 19.3, MEDIAN 0), so
          the "+-6" standard error I quoted for 110 HP is too optimistic. **Retrofitting the L1-2 kit to a
          single band of 20 deaths would be fitting a tail.** Not done.
        * **What IS clear is a LEVEL-SCALING gap, from L6 up, in two places** (live deaths vs sim "average",
          matched on level/class/race): **base CON** live 10.2 / 11.8 / 17.2 / 19.1 vs sim 10.1 / 11.3 / 13.0 /
          11.7 for L1-2 / 3-5 / 6-9 / 10-24 (STR is close: 16.6 vs 14.5 at L10-24) - live players put most
          level-up stat points into CON and the sim's player does not; and **gear `hp_bonus` per kit** live
          8 / 38 / 80 / 188 vs sim 19 / 21 / 36 / 61. Together they are the 482-vs-255 HP gap at L10-24.
        * **Revised step (1), for the BALANCE BATCH:** model the stat-point spend (`make_char` leaves
          `unspent_stat_points` 0 and the points nowhere; fit a CON-heavy split from the live stats, n=60 deaths
          + the living L57/L91 characters), and decide how gear affix magnitude should scale with level for
          the reference player (the generator is shared, so this is probably dungeon/chest loot the drop model
          does not give an "average" player). Both only matter from L6 up, where the deaths are few (6 of 63
          deaths are above L9), so this is lower leverage than it first looked; the L1-5 mismatch is
          within noise of the current fit.
        * **So the early-game deaths (L1-2, 68% of all) are NOT explained by a too-strong reference player.**
          Their cause is still open: next measurement is the fights themselves (monster level vs player HP
          at the start of each death, per class), not the kit. Tricksters are 54% of deaths at base stats
          identical to everyone's - look at the CLASS side first (decks / resource pools at L1-2), per
          `feedback_check_the_instrument_first`: card and policy before class.
      ▶ **REFERENCE PLAYER vs LIVE DEATHS, RUN 2026-10-13 (step 3).** Sample: the 60 deaths since the
      2026-09-05 cutoff at L1-24 (the dying population, which the 2026-09-18 fit also used), compared with
      `make_char(level, "average", class, race)` for the SAME (level, class, race) of each death, 6 draws each.
      Pulled read-only over SSH; the characters dir was deleted again after use.

      | band | n | live maxHP (+-sem) | sim maxHP | live item lvl / sim | live slots / sim | verdict |
      |---|---|---|---|---|---|---|
      | L1-2 | 20 | 110 (+-6) | **140** | 1.2 / 1.0 | 5.0 / 4.5 | **sim 27% TOO TANKY (~5 sem)** |
      | L3-5 | 18 | 157 (+-15) | 147 | 2.1 / 1.3 | 6.1 / 4.4 | agrees |
      | L6-9 | 5 | 286 (+-78) | 190 | 4.9 / 3.3 | 7.0 / 5.7 | sim low, n too small to say |
      | L10-24 | 17 | 482 (+-55) | **255** | 15.0 / 7.1 | 6.5 / 6.2 | **sim ~half the live HP (~4 sem), gear 2x** |

      * **L1-2 cause, measured:** base stats are IDENTICAL (CON 10.1 vs 10.2, STR 10.1 vs 10.1, ...), so
        it is the GEAR. Live L1-2 kits carry `hp_bonus` **7.7** per kit (n=20); the sim's kit carries
        **24.6** (`gear_model_matches_live`). The 2026-09-18 fit used a live mean of 22.6 from a different
        population; for the deaths at L1-2 specifically the sim kit is ~3x richer in HP affixes. Live gear
        there is 93% common at item level 1.2 and mostly carries stat affixes (wis/wits/str bonus), not HP.
      * **So the sim's L1-2 player is stronger than the real one, monsters are sized against it, and the
        real L1-2 player faces monsters tuned for someone ~27% tougher.** That fits the death data (68% of
        deaths at L1-9, most at L1-2, 32 of 49 at parity). It is the first quantitative reason to believe
        the early curve is too hard for the player who actually exists, rather than just a count.
      * **L10-24 is the opposite direction:** live dying characters carry item level ~15 (sim ~7), more
        uncommon/rare gear, and 480 HP vs 255. They found better gear than the drop model gives an
        "average" player (dungeon floors, chests, minigame loot - the sim models drops only). This band has
        n=17 and is DEAD characters only, so it is biased toward people who pushed on; do not fit to it
        blindly.
      * **NOT ACTED ON, by the owner's own batching rule.** Both findings change the reference player, which
        invalidates the curve and means the whole chain (speciescal -> refcal -> rolecal) must be re-run
        once afterwards. Proposed for the BALANCE BATCH, in order: (1) make the L1-2 kit's HP affixes match
        live (`LOW_LEVEL_WEAR` already converts rarity; it does not shrink affix VALUES); (2) decide whether
        the L10+ reference player should carry dungeon-found gear, using the living L50+ characters (L57, L91)
        as the unbiased check; (3) then `preflight`, then the chain ONCE. Caveats: deaths-only sample;
        L6-9 n=5; I did not re-derive the 22.6 figure, so (1) might be partly my sample choice - re-measure
        on the same population the fit used before editing.


      ⚑ **THE DATA IT WAS WAITING ON IS NOW DUE (owner, 2026-10-13: "it's been a few weeks, we
      should have better data").** The 2026-09-19 handoff said re-run `tools/death_log_audit.py`
      "in ~2 weeks" against the 1.81% deaths-per-encounter baseline; that was due ~2026-10-03,
      and 24 days have now passed. **Do this BEFORE touching any item below or running the
      chain:** (1) `python tools/death_log_audit.py` (live deaths, by band/class/level gap);
      (2) `bash tools/check_player_progress.sh` (how far the live population climbed, split by
      era); (3) re-check the reference player against live saves
      (memory `reference_live_reference_player`: `make_char` carried 189 maxHP vs a real ~109
      once, and the chain cannot see that). Both scripts are READ-ONLY over SSH. Only then batch
      the items below - [25] and [27] in particular should be judged against real deaths, not
      the sim. [25 Fighter mitigation looks
      permanently capped (is Bulwark/Brace applying unused?) — investigate as a BUG first;
      27 uneven monster damage; 33 Chaos/Magic Bolt variance; 41 Paths maxed too fast (overlaps
      existing PATHS REVAMP item ~7420); 38 minigame reward tiers — egg of faced monster or
      same-tier, rarer than low ones; 48 Jarl powers / empty realm treasury].

11. - [ ] **NEW DIRECTION 2026-10-13 (owner, after the sheet) — VARIETY: quest boards, monsters,
      companions, and the tank mobs.** Four linked asks, recorded together because they share
      inputs. **Placement: DESIGN FIRST, then the BALANCE BATCH** - every one of them changes monster
      or companion power, so per CLAUDE.md they invalidate the calibration chain and must land
      BEFORE the one chain run, not after it.
      (a) **QUEST BOARDS LACK VARIETY AND GIVE NO REASON TO VISIT.** Owner: *"They all send you to
      pretty much the same couple of monster types and also don't really incentivize players to
      come to them (unique varieties, patterns, or traits, etc.)."* Two halves: the quest
      GENERATOR picks from too small a pool of targets (measure it first - count distinct
      monster/dungeon types across a few hundred generated boards; do not assume), and a board
      offers nothing you cannot get elsewhere. A board should be where you go to find a SPECIFIC
      variety/pattern/trait you want (ties straight into (b) and (c)). Overlaps sheet items 35, 38
      and the existing "Real sinks for excess eggs and companions" and dungeon-questing items.
      (b) **MONSTERS WITH ROLLED STATS.** Owner: *"Perhaps monsters get randomized stats so not all
      monsters of the same rank/tier are the same and even two of the same monsters could be
      different due to how they roll."* Today a monster's stats derive from a level curve plus a
      per-species multiplier (`species_power`) and a role multiplier - deterministic per
      (species, level, role). Needs a DESIGN pass before code: how wide a roll, whether it is
      visible (a variance the player cannot see is noise, not variety), whether it is a trait
      ("Thick-hided", "Frenzied") so it can be named on the log (sheet item 19) and offered on a
      board (a). Must keep the MEAN on the curve or the calibration is silently shifted.
      (c) **COMPANIONS NEED MORE VARIETY.** Owner: *"We may need to consider a way to make companions
      have even more variety."* Companions are the monster you kill/hatch, so (b) feeds this
      directly: a rolled-stats monster yields a rolled-stats companion. Existing per-INSTANCE
      work is relevant (memory `project_card_instances_chase_loop`: duplicates must level
      independently) and the cosmetic-variety work (variants/colours/patterns). Decide whether a
      companion's rolls are inherited from the monster it came from. Related: item 51 (same
      companion in several slots) must be settled first or variety can be duplicated away.
      **OWNER CLARIFICATION 2026-10-14: 'THE TANK MOBS' IN (d) MEANT TANK *COMPANIONS*, NOT TANKY MONSTERS.** Everything under (d) below that talks about monster species, `species_power` and the monster death log was written under the wrong reading - treat it as background only. The live lead is companion tanks: a companion's HP pool is solved from its AGGRO as a share of the owner's bar (`Character.calculate_companion_max_hp`), so a high-aggro tank gets the largest pool AND soaks the most hits. **Measure it with the companion audits (`-- spread`, the companion probes) before tuning, and settle it inside item 14's S0/S1 (roles), because tank is one of the five roles being designed.**
      **TESTED AND REJECTED 2026-10-14 (item 9 session): 'Glass Cannon (x3 strength / x0.5 HP) causes the L100 death hump'.** `-- forensics` showed Titan (10% of L100 spawns) at ~7x its neighbours' strength via that ability, so I softened it to x2 / x0.65 and measured with the 270-fight `riskcurve`: average-gear L100 death 8.1% -> 8.5% (noise is ~+/-1.7 pts) - NO effect, so the change was REVERTED and nothing shipped. What the encounter lines DO show: at L100 average gear most deaths are EMPOWERED monsters (12 of 22 shipped; 19 of 23 in the second run) - which matches the live log (11 of 13) and the owner's standing direction that empowered difficulty 'may need reduced slightly'. Experiment in progress: empowered win target 0.50 -> 0.58 in `ROLE_TARGETS`, `rolecal` on the candidate base, then `riskcurve`.
      (d) **[CLARIFIED 2026-10-14: this is about TANK COMPANIONS - see the note above] THE TANK MOBS ARE CRAZY STRONGER THAN THE OTHER VARIETIES.** Owner: *"The tank mobs
      being crazy stronger than the other varieties needs to be on the backlog."* **MEASURE BEFORE
      TUNING, and suspect the instrument first** (CLAUDE.md): `species_power` has never once
      weakened a species - every correction is a strengthening, 68 of 136 pinned at the x2.50
      ceiling - so an outsized tank archetype is exactly what a one-sided calibrator would
      produce. Do NOT widen the clamp (documented: it amplifies the bias). Start with the live
      death log (`tools/death_log_audit.py`, now DUE - see item 9) broken out BY MONSTER
      ARCHETYPE, then `-- spread` / `-- forensics` (read-only) on the tank species. Belongs to
      the BALANCE BATCH, judged against absolute targets, not against sibling varieties
      (memory `feedback_tune_to_targets_not_to_each_other`).

12. - [ ] **IDEA (owner, 2026-10-13, mid-session) — KEEP THE GAME FRESH: scheduled restarts that
      reshuffle the map, and server-wide EVENTS.** Recorded as stated; NOT scheduled, NOT designed.
      (a) **Restart every ~3 hours with a RANDOMISED MAP** - "like a wipe but the market listings
      don't disappear": listings are re-assigned to posts on the new map; player STRUCTURES/OUTPOSTS
      keep their coordinates and owners; a true wipe maybe every ~3 months.
      (b) **A good EVENT per restart, lasting until the next one** - grand buffs and variants, e.g.
      players get double the actions of enemies, valor x3, eggs far more common, sharper weapons
      (high attack/primary stat) and sturdier armour (high HP) more prevalent, "and some others".
      **Things this must be designed against BEFORE any code (my read, for the owner to rule on):**
      - *Structures vs a new map.* Structures stay at the same coordinates, but the terrain under
        them changes: an outpost could land in water/void or inside a different biome/level band.
        Either the map is randomised AROUND fixed structure footprints, or structures get re-seated.
        This is the hard part and it is not obvious which the owner wants.
      - *Everything that is keyed on the map.* Post-anchored levels, the threat/dungeon system (3,000
        world dungeons that live <=24h anyway), quest boards naming posts, the Atlas/cartography the
        player has discovered, home stones/sanctuary, tutorial walk to the first dungeon, "post
        distribution" rules measured on 2026-09-13. All assume a map that persists for weeks.
      - *Permadeath + 3-hour churn.* Players who navigate by memory lose the whole map every 3 hours;
        the long walks the curve already imposes (L100 at radius ~900) get re-rolled each time.
        Needs the travel/stance/post-network work to be solid first, or it will read as punishment.
      - *Events change player power, so they touch the calibration* (CLAUDE.md: any player-side
        change invalidates the monster curve). x2 actions / x3 valor are not a balance change if they
        are clearly an EVENT, but the chain, the death-log audit and `refcal` must be able to tell
        event time from normal time (tag event sessions, or the live data stops being usable for
        balance - and live data is exactly what the BALANCE BATCH is waiting on).
      - *Valor x3 and eggs/gear drops are economy sources* (see the valor-economy and egg-sink items):
        a 3-hour cycle of "everything is tripled" inflates both unless sinks exist first.
      **Sequencing:** DESIGN ONLY until the BALANCE BATCH has run once and the economy sinks (items
      10 / 50) exist. The EVENT half (b) is separable and much cheaper than the MAP half (a): events
      could ship alone on a daily/weekly cadence as a first slice, and a restart cadence is already
      supported by the warned-shutdown machinery. Overlaps 11(a) (reasons to visit boards) and
      11(b) (variants/rolled monsters could be an event's "variants").

` and
        normalised the read), `companion_lines_are_marked`, `companion_trail`, `sanctuary_room`,
        `danger_step_guard` (its second check). **Cause:** the repo's rule is `* text=auto eol=lf`, but
        THIS working tree is mixed - 8 big sources (`client.gd`, `combat_manager.gd`,
        `dungeon_database.gd`, ...) are CRLF, the other 76 LF, and 21 probes CRLF - and a probe with a
        `
` needle fails against a CRLF source while a CRLF probe's raw-newline literal fails
        against an LF one. (I flipped `server.gd` to LF myself via `git checkout` earlier today;
        harmless to git, but it is how that probe started failing.) **Structural fix:** normalise the
        working tree to LF (what `.gitattributes` already declares; git sees no change) and have
        `probe_run.py` fail when a tracked `.gd` is `w/crlf`; or make every probe read sources
        through a `
 -> 
` normaliser.
      - *Counts that moved because code was added on purpose (4):* `dungeon_index` (6 creators / 2
        erases - the Phantom creator and its rollback), `dungeon_instance_match` (5 call sites - the
        Cartographer path), `dungeon_variety` (the `_OverworldRoom.build(...)` call gained args),
        `overworld_render` (retired text-map mode cut the fallback returns to 1). Better to assert the
        RULE (every erase follows `_unindex_dungeon`) than a count.
      - *Feature or text deliberately changed (9):* `card_instances` (deck screen rebuilt to one tile
        per copy; '+' still restores a benched copy), `empowered_hover` (hover wiring moved into
        `_wire_hover`), `depleted_looks_spent` (a spent node now reads "empty"/"!hotdepleted" by
        design), `help_topics` ("CRAFTING & GATHERING" split into two topics), `dungeon_redraw_guard`
        (guard now reads `_fight_log_open()`, the probe sets a dead bool),
        `inventory_pressure_and_autosalvage` (the keep filter matches stat keys, not affix names - on
        purpose), `quest_grade_advertised` (grade variance `varied_grade` is deliberate; advertised ==
        stamped still holds), `engine_ramp` (client reads `CombatManager.BARBARIAN_RAGE_DMG_PER` to
        DISPLAY it - a read, not a copy), `dungeon_placement` (**my own rewrite of the world roll today
        - intended**; the uniform property is covered by `world_dungeon_roll_is_uniform`).
      - *Retired features (2):* `overworld_toggle` (the sprites toggle was removed in 20d96d51 -
        delete the probe), `party_confirm` (the confirm state was removed deliberately in a10c3833
        after the owner got stuck in it - delete or rewrite around "Change action"; the dead
        `_party_confirm_*` code can go too).
      - *Probe bugs of their own (4):* `map_payload` (400-char window now ends inside a comment
        block), `hover_reachable` (matches same-named locals), `power_rank` (its banned-phrase scan
        matches a `##` comment), `escort_walks_around_danger` (its sample never crosses the one
        hotzone, so it proves nothing - the Warden's avoidance itself was verified to work by hand:
        5 hotzone tiles on the plain route, 0 on the safe one), plus `map_payload_golden` (stale
        baseline from 2026-09-13; world generation has changed - re-capture deliberately).
      **FIXED 2026-10-13 (after the triage): ALL 29 NOW PASS** the strict runner (27 fixed, 2 deleted as
      retired features, `launcher_selfupdate` was never failing). What was done, and what the triage
      got WRONG: the agents missed failing checks - `card_instances` had a second one (a probe that
      overwrote the hand and so created a duplicate card; the game was right) and `overworld_render`
      had four more (retired toggle, `_bob` added to the figure anchor) - so every "only one check
      fails" claim was re-run and re-read before being trusted. **Line endings:** the working tree is
      now LF throughout, matching `.gitattributes` (43 files converted, git sees no change);
      `probe_run.py` REFUSES TO RUN if any tracked file is CRLF in the working tree and
      `--fix-eol` repairs it (proven to fire). **Real game fixes, in the NEXT client release (not yet
      shipped):** initiative help text now states the solo 5-75% clamp, the stance modifiers
      (Travelling +18, Scouting -4, Hunting -8) and that a party fight is a simpler formula capped at
      55%; the "Know This Foe" button uses a BMP glyph (`☰`) - same font-fallback mechanism as the
      `★ ◆` already used, but NOT visually confirmed (the button did not appear in the capture); and
      the GATHERING help topic again explains the scratch-off grid vs the deep-water 3-choice chain
      (the "CRAFTING & GATHERING" split had silently dropped it).
      **RESOLVED 2026-10-13, shipping in v0.9.835 (owner: "release it with the server deploy"):**
      - [x] *Danger-step wording - DONE, with the variety the owner asked for.* New
        `shared/danger_words.gd` owns the verdict edges (0.6 / 0.85 / **1.15** / 2.0 / 3.0) AND the
        words; the server guard builds its message from it and the client's Area readout builds its
        verdict from it, so they cannot disagree again. `DANGER_STEP_RATIO` is defined FROM it, so
        "where the guard asks" and "where the readout turns red" are one number. **Behaviour change:**
        the readout now turns red at 1.15x (it was 1.35x). The warning has 4 phrasings per verdict x 4
        openers x 3 tails (44 distinct per verdict measured); every variant names the ground's level,
        yours, the readout's own phrase, and "to go anyway". Probe `danger_words_agree.gd`, fault-
        injected both ways (thresholds drifting apart; wrong verdict phrase) - both fail it.
      - [x] *Client-trusted `escorted` flag - FIXED.* The dispatcher strips `escorted` from network
        move messages; the Warden's two internal calls still set it. Probe
        `escort_flag_is_server_only.gd` (fails if the strip is removed). Not visible to players.
      **STILL OPEN (owner decisions):**
      - *Solo vs party initiative* (5-75% with stance vs 5-55% without). Owner's read: probably DRIFT,
        not design. **Not changed in the release on purpose:** making party fights use the solo
        formula changes how often monsters strike first in a party - a balance change, which belongs
        in the BALANCE BATCH and must be measured, not slipped into a text-and-safety release. The help
        text states what each path really does. When it is done, delete the party-specific note.
      - *`map_payload_golden` is not hermetic* (no decision needed - a known limitation, not a
        question): it reads the machine's saved seed and posts from `user://`. Re-captured today with
        the reason in its header; inject a fixed seed and posts before trusting it as a gate.
      **RE-SWEEP AFTER v0.9.835 (2026-10-13, owner: "run the full sweep again"): 340 probes, 254 clean,
      86 not green (was 227 / 113).** Breakdown: 10 print script errors, 1 reports its own FAIL, 74 print
      no verdict the runner recognises, 1 exits non-zero with no FAIL text (`ui_scale_1080p`), 0 hang.
      **The sweep found two FLAKY probes that had passed the first time - the lesson is that one green
      run proves little for a probe with randomness in it:**
      - `a_telegraph_is_answerable` failed ~24% of runs (6 of 25). Cause: it generated a random monster, and
        one random modifier is Juggernaut ("immune to stun, shrugs it off and acts anyway", correct game
        behaviour), so "a stun cancels the burst" sometimes failed. Fixed (boss pinned to no modifiers,
        seeded per fight): 40 of 40.
      - `dungeon_modifiers` failed ~40% (10 of 25 as a nil call on `monster_db`, a bare-server gap; once
        that was supplied, the SAME runs failed the HP/damage checks because a rank-9 monster has a 45%
        chance of an extra Empowered modifier before the dungeon multipliers apply - also correct game
        behaviour). Fixed (database supplied; the "nasty" dungeon sits at rank 2, which never empowers):
        40 of 40.
      - **TODO: give `probe_run.py` a `--repeat N`** and run the randomised probes several times in the
        sweep, so a flake is reported as a flake instead of as luck. Until then a single pass of a
        probe that calls `randi()`/`randf()`/`generate_monster` is weak evidence.
      - The sweep also REWRITES a tracked file (`docs/design/companion_variants_review.md`, a probe
        regenerates it); I revert it by hand each time. A probe should not write into tracked docs.
      - **A THIRD flake, in the RELEASE GATE itself (2026-10-13):** one `--smoke` run reported "1 failed"
        and ten consecutive reruns did not (150 probe-runs, plus 60 of `floor_loot` and 40 of
        `danger_step_guard` alone). I could not name the probe from that one run, which is the weakness:
        the runner printed only the count at that moment. Most likely suspect, and now fixed:
        `danger_step_guard`'s wall-clock check (182 us against a 200 us limit, one batch) - now the best
        of five batches. `lazy_dungeon_interior`'s timing is a LOWER bound and cannot fail under load.
        **UNCONFIRMED** that this was the cause. If the gate ever blocks a release, rerun it once before
        believing it, and read which probe failed - the runner prints it.
      - **The 74 "no verdict" probes, CHARACTERISED (all 74 re-run): none is silent, and most are not
        tests at all.** They print tables, "X initialized" lines, "measurement only - the shape is the
        finding" notes or a diagnostic number (e.g. `card_bonus_fit`, `dungeon_spread`, `kill_investment`,
        `comp_hp_probe`, `divine_check`, `companion_variety`, `consumable_clarity`) - MEASUREMENT TOOLS that
        happen to live in `tools/probe/`, with no pass/fail to find. Two print `RESULT: PASS (N failing)`,
        a format the runner did not know - now recognised. **Decision to make:** move the measurement-only
        scripts to `tools/measure/` (so `--all` means "the tests") or give each a real verdict; do not make
        the runner pass them. `ui_scale_1080p` exits non-zero with no FAIL text and needs a read of its own.
      **Consequence:** `probe_run.py --all` is NOT a usable gate yet; only `--smoke` is. Triage order
      that costs least: (1) the 74 verdict formats (mechanical), (2) the 9 script-error probes
      (probe rot), (3) the 29 FAILs one by one, deciding stale-vs-regression for each. Report:
      the sweep's own output was kept in the session scratchpad, not the repo - re-run
      `python tools/probe_run.py --all --report sweep.txt` (about 25 minutes, one probe at a time).

14. - [ ] **VISION (owner, 2026-10-14) — STRATEGIC PARTY COMBAT, THROUGH COMPANIONS.** Recorded as
      the owner stated it, plus three design rulings made in the same conversation. **DESIGN FIRST;
      NOT scheduled, NOT started.** Owner: *"When we rework companion roles like the tank etc. We
      should begin going towards one of the next visions for the game. I'd like to get our combat
      more towards the strategic type from turn based rpgs. Ones that involve buffing and healing of
      party members. Effectively I'd like to do this through our companions."*
      **THE SHAPE:** give companions ROLES (tank, healer, buffer, striker, controller ...) and let a
      player field **up to 5 companions: 4 shown in the right-hand column like party members, 1
      beside the player on their own card** (as the single companion sits today). Party play stays
      capped at the right-hand slots, so a column can be all humans, all companions, or a mix.
      **RULINGS (owner, same conversation) - these are decided, do not re-ask:**
      - *Command model: companions act on their own AI and the player sets a TACTICS FOCUS* - "all
        out, healing, buffing, etc." Not a per-companion command menu, and not role cards dealt into
        the player's hand (both offered and declined).
      - *Companions are REVIVABLE, never lost to a KO* (owner, 2026-10-14): by consumable items, by
        another companion's ability, by a wandering healer, and at a trading post. ALREADY BUILT:
        the Revive Potion and the healer NPC. NEW: a companion ability that revives an ally
        (a healer-role action), and confirming the trading-post route is the same healer service.
      - *TACTICS FOCUS IS PER COMPANION*, not one global setting.
      - *AT LEAST FIVE ROLES:* **Tank, Healer, DPS, Utility, Jack-of-all-trades.** A companion's role
        comes from its **SPECIES normally**; the owner is open to VARIANTS (and other things) influencing
        it. Treat "species sets the role, variant can tilt or modify it" as the starting hypothesis
        for S0, not a ruling.
      - *The 5th companion sits BESIDE the player*, not in the column. The column holds 4.
      - *In a party the 4 right-hand slots are SHARED across the party* (split between players, not
        first-come), and every player keeps their beside-you companion on their own card even in a
        party: *"players usually have at least one companion with them even in party play next to
        them in their card."* Solo: four in the column plus one beside you.
      **WHAT THE CODE IS TODAY (read 2026-10-14, so the design starts from facts):** a companion is
      ONE AI helper. Its abilities are species-tier passives / chance / threshold effects
      (`COMPANION_MONSTER_ABILITIES`), its only "role" is an AGGRO percent - the share of monster hits
      it soaks - and its max HP is SOLVED FROM THAT AGGRO as a share of the owner's bar
      (`calculate_companion_max_hp`). **CORRECTED 2026-10-14 (I first wrote that it has no HP pool -
      wrong):** it DOES have a persistent combat HP pool (`get_companion_combat_hp` /
      `set_companion_combat_hp`, stored on `active_companion`), a KNOCKED-OUT state
      (`is_companion_ko`; natural regen skips a KO'd companion), a `potion_revive_companion` item, and
      the healer NPC encounter already shows and revives a KO'd companion. What does NOT exist is that
      pool for companions BEYOND the active one, or any companion healing another. Party max is 5
      (`PARTY_MAX_SIZE`), each member has their own deck and hand, and the right column is
      `combat_scene_panel._party_column` drawn from `set_party_members()`. `active_companion` is read
      in hundreds of places (corpse, registered/`house_slot`, trades, stable, death) - a data-model
      change there needs an ADAPTER (`active_companion` stays as the beside-you slot), not a rename.
      **ORDER (each slice shippable and probed on its own; do them in this order):**
      - **S1 BUILT 2026-10-15, UNRELEASED, UI UNSEEN.** `shared/companion_roles.gd` (species->role table: 53 species = 15 Tank / 13 Utility / 11 Striker / 8 Healer (theme override list) / 6 Jack; `choose_action`; every magnitude and cap), `combat_manager._companion_role_choice` / `_companion_role_action` (a support action REPLACES the companion's attack; cooldown 2), `Character.set_companion_tactics` (travels with the companion through activation), server `set_companion_tactics`, and a visible **Tactics: <focus>** button plus Role/Tactics lines on the Companions panel (cycles Balanced > All out > Protect > Support). Probe `companion_roles_act` (5 fight-turn checks fail on the old combat code, all pass now). **NOT DONE / NEXT:** (1) the panel button is untested visually - needs an owner screenshot after release; (2) Revive-an-ally and ally healing wait for S2/S3 (no allies yet); (3) this adds player power, so the monster curve is stale until the item-14 chain run - do NOT ship it as a balance change alone; (4) changelog + help text at release.
      - **S2 BUILT 2026-10-15, UNRELEASED, NO UI YET.** `Character.companion_party` = up to 4 companion IDS (column slots); `active_companion` stays slot 0 / beside-you, untouched. Reads go through `get_companion_party_ids()`, which DROPS any id that left the collection, is the active one, is duplicated, or exceeds the unlocked slots - so release / trade / register / death never need to know the list exists (that is how the ~15 collection-mutating sites were audited: they don't have to be). Each fielded companion has its own persisted HP pool and KO state (`get_party_companion_combat_hp` etc.). Slots unlock at character level **10 / 25 / 50 / 100 - FIRST GUESS, unmeasured**. Registered (Sanctuary) companions may be fielded; they return by their house slot as today and the list prunes itself. Probe `companion_party_model` (28 checks). **NEXT:** S3 combat engine (several companion actors, monster targeting across them, the simulator modelling the team FIRST), then S4 UI + server add/remove handlers.
      - **S3 BUILT 2026-10-15, UNRELEASED, UI UNSEEN - AND IT CHANGES WHAT THE CHAIN MEANS.** Combat: column companions act after the beside-you one (`_process_companion_team`), each with its own HP/KO, role and tactics; the monster picks its target across every standing companion weighted by aggro (with ONE companion this reduces exactly to the old roll - probe: wolf 23% vs 25% expected, wolf+Iron Golem 75%); a Healer heals the LOWEST ally (you or a companion) and REVIVES a fallen one (cooldown 3, 25% HP); column companions earn the same victory XP, recover with rest (not when KO'd) and the healer NPC revives them. A column companion's output is `TEAM_MEMBER_MULT` 0.375 of the beside-you one (1 + 4 x 0.375 = the 2.5x team the owner chose). Probes `companion_team_combat`, `sim_models_the_companion_team`. Simulator: `-- <audit> --team` fields the full team (REFUSED for refcal/speciescal/rolecal - they fit to the companion-free reference player). **CORRECTION TO MY EARLIER CLAIM:** the chain's reference player has NO companion by design (`_companion_mode = none`; companions are a bonus on top), so adding companions does NOT invalidate the curve and no chain re-run is needed for them. What they change is the DEATH RATE REAL PLAYERS SEE. **MEASURED (riskcurve --team, 270 fights/cell, death % per fight):** average gear L3/10/30/100/500: shipped curve, no team 0.4/1.9/1.9/8.1/5.2 -> shipped curve WITH team 0.0/0.0/0.7/0.0/0.0; CANDIDATE curve WITH team 0.7/0.7/0.4/0.0/0.0. So a player with a full team meets the owner's condition ('death risk must not get worse') even on the harder candidate curve. **THE CATCH:** 'under'-geared characters have no companions in the sim's model and stay worse on the candidate (L100 5.9->9.6, L500 5.6->15.6), and characters below level 10 have no column slots at all. **THE TEAM IS ALSO PROBABLY TOO STRONG:** ~0% death at average gear means the survivability side (4 extra HP pools soaking up to 80% of hits) is far past '2.5x output'. Tuning is S6; first decision for the owner is whether to scale the team's soak (e.g. cap total team aggro below 80, or lower member HP shares) before shipping the candidate curve. Data: `docs/balance/data/riskcurve_270_team_*`. **NEXT:** S4 UI (column cards, add/remove, tactics per companion) - needs screenshots; S5 acquisition; S6 calibration.
      - **S3 CORRECTION 2026-10-15 (supersedes the 'team is far too strong' claim above - that was an INSTRUMENT ARTIFACT).** The sim's `match` companion is the player's LEVEL and a HIGH tier; the rank-1 Sorcerer's real one was a tier-4 Hydra at level 53 against his L91. New sim mode `lag` (tier = 1+level/24, level = 60% of the owner's) is the realistic one and `--team`/`--companion` now use it. Also measured: ONE matched companion alone already gave 0% average-gear death, so the team was never the driver. Applied (owner approved 'cap the team's soak'): `TEAM_AGGRO_CAP` 50 - a team of 2+ soaks at most 50% of hits (probe: wolf+golem 48%); a lone companion keeps its old ceiling of 80. **REALISTIC DEATH % per fight, average gear L3/10/30/100/500:** shipped curve, no companion 0.4/1.9/1.9/8.1/5.2; shipped + ONE lagging companion 0.0/0.7/1.9/2.2/0.0; shipped + full team 0.0/0.0/1.1/1.5/0.0; CANDIDATE (tougher) curve + one companion 0.4/3.0/2.6/1.9/0.0; CANDIDATE + team 0.4/1.1/1.5/0.7/0.0. **So with a team the candidate curve is no worse than the shipped game with one companion - the owner's shipping condition is met for players WITH companions.** Still worse on the candidate: UNDER-geared (the sim gives them no companion): L100 5.9->7.0, L500 5.6->15.6 with team off - decide whether 'under-geared' players should have companions in the model before shipping it. Logs: `docs/balance/data/riskcurve_270_lag_*.txt`. Ships only with the item-14 UI (S4), otherwise nobody can field a team.
      - **S4 BUILT 2026-10-15 (FIRST CUT), UNRELEASED, NOT YET SEEN ON SCREEN.** Companions panel (More > Companions): a **Team** section under the active companion - slots used/unlocked, one row per column companion with role, HP/KO, a per-companion **Tactics: <focus>** button and **Remove**; right-click any other companion -> **Add to team / Remove from team**; locked characters are told the unlock levels (10/25/50/100). Server: `field_companion`, `unfield_companion`, `set_companion_tactics` (now takes an `id`). Combat scene: in SOLO fights the column companions appear in the right-hand column as party cards with the human half hidden, name tagged `[Role]`, own HP bar, `(KO)` marker (`_apply_companion_team_to_panel`; `combat_state.companion_team` carries their derived HP). Probes `companion_team_panel`, `companion_team_cards` (nodes, text, wiring - NOT pixels). **KNOWN GAPS / NEXT:** (1) owner screenshots of the Companions panel and a solo fight with a team - card sizing/overlap is unverified; (2) PARTY play: the humans' cards own the column, so a party member's own team is not drawn (the engine's party path may not run the team at all - check `_apply_party_member_companion` before promising it); (3) team HP bars update when the state arrives, not beat-by-beat during paced playback; (4) the beside-you companion has no role/tactics line on its combat card; (5) help text + changelog at release; (6) S5 acquisition/economy (how a player gets role-diverse companions) and S6 calibration.
      - **RELEASED 2026-10-15 as v0.9.842 (client + server, hash `92ba16e82a5627bd` verified).** S1-S4 are LIVE: roles, tactics, the team (slots 10/25/50/100), the Companions-panel Team section, column cards in solo fights, healer NPC revives the team. Screenshots made with `tools/team_ui_shots.gd` (windowed run; writes `claude_screenshots/team_combat.png` and `team_companions_panel.png`) - the combat cards fit and read well; no real-client screenshot yet. STILL OPEN under item 14: party-play teams, a role/tactics line on the beside-you companion's combat card, paced-playback HP bars for teammates, S5 acquisition/economy, S6 (decide the tougher candidate curve now that teams exist - see S3 CORRECTION), and a live feel check of how strong the team is.
      - **S5 (ROLE ACCESS) BUILT 2026-10-15, v0.9.843.** FACTS: every one of the 53 species has exactly ONE dungeon whose boss egg is that species, so role-diverse companions were always obtainable - nothing SAID which dungeon gives which role, and there was no Striker before tier 4. OWNER DECIDED: show roles + a role fusion; Wolf/Gnoll/Orc named Strikers. BUILT: roles named on companion cards, eggs, inspect, the Stable lists and the **Dungeon Atlas egg line**; **Role Swap** at the Stable (`fusion_type` `role:<role>`): 3 companions of ONE tier + 1,000 gold/tier -> 1 companion of the chosen role (random species of it at that tier, else the nearest tier that has it), grade kept, RANK = the lowest of the three, best level and border carry - a swap, never an upgrade. Probes `role_fusion` (real handler: result role, grade, rank, level, border, gold; refusals take nothing). Screenshot `claude_screenshots/team_role_swap.png`. **STILL OPEN under S5 (the economy half):** the 1,000 gold/tier price is an unmeasured first guess; no upkeep exists for companions (the team recovers free with rest and the Healer NPC charges Valor); egg/companion SINKS beyond this fusion (item 'Real sinks for excess eggs and companions' stays open); 11(c) rolled companion stats. Gold sink check: Role Swap at tier 6 costs 6,000 gold - compare with Temper (5 tiers/item, 500..5,249 at L50) before tuning.
      - **PARTY-PLAY TEAMS BUILT 2026-10-15, v0.9.844 (supersedes the 'teams are not used in party fights' gap).** FINDING: the party engine runs each member's action AND the monster's attacks on that member through a solo-shaped view tied to the member's own Character, so every member's column team already acted, got targeted and was healed in a party; `view_carry` keeps per-companion cooldowns between actions. My v0.9.842 changelog/help said otherwise and was wrong (corrected). BUILT: the four column slots are shared - `CompanionRoles.party_team_cap(n)` = 4 alone, 1 each in a pair, 0 from three up (what is left after every other human takes a slot, split evenly); applied through `Character.team_cap_override`, set only while a member is ACTING (`_party_member_view_acting`, lifted by `_party_sync_view_back`) and never touching the stored team; the server's `_party_combat_snapshot` carries each member's trimmed `team`; the client draws everyone's teammates after the humans, tagged with the owner. Probe `party_teams` (real round functions). Screenshot `claude_screenshots/team_party_combat.png`. **FIXED IN THE SAME RELEASE:** `_party_combat_snapshot` computed a party member's beside-you companion max HP with the old `30 + level*5 + ...` formula, so a teammate's companion bar disagreed with its owner's screen - it now sends the stamped value. **KNOWN LEFT:** (2) the cap rule is my reading of the owner's 'split between players' - confirm it feels right in a real pair; (3) a 3+ party has no column companions at all.
      - **ITEM 14 STATUS 2026-10-15 (v0.9.844): S0-S5 and party-play teams are LIVE. What remains is S5's economy half (folded into Wave 1's economy design) and S6 calibration (Wave 2). Details of each slice follow, newest first.**
      - **S0 STATUS 2026-10-15: DRAFTED in `docs/design/companion_roles_s0.md`.** Owner decided: Healer = theme-pick ~8 species via an override table (only 3 of 53 species are natural healers); slots unlock by progression; full team ~2.5x one companion's output. Rulings 1-7 in the doc (roles, role actions, tactics, per-companion HP/KO and revive costs, aggro targeting, caps, companions help humans) await a yes. Next: S1.
      - **S0 DESIGN, no code.** Settle: (1) the five-plus ROLES (Tank, Healer, DPS, Utility, Jack-of-all-trades are
        ruled; add more only if a gap shows) and how a species gets one - DERIVE it from existing
        species data (aggro, ability tags) through one table, like `species_power`, rather than
        hand-authoring 136 species, then decide what a VARIANT may tilt; (2) the TACTICS list and what each does per role;
        (3) the HP pool for EVERY fielded companion (today only the active one has one) and the revive
        rules - a KO is recoverable (ruled), so settle the COST of each route (a potion, an ally's
        action, the wandering healer, a trading post) so none of them is free and none is mandatory; (4) THREAT/TARGETING - how a monster picks between the
        player, humans and companions, how taunt/aggro works, and whether AoE exists; (5) heal and
        buff magnitudes and STACKING CAPS (the old uncapped blacksmith upgrade is the cautionary
        tale); (6) whether companions heal/buff HUMAN party members (the vision says yes - it is the
        reason a party and its companions interlock); (7) THE CORE BALANCE QUESTION: a player with
        five companions fields roughly double the force. Either monsters scale up as they do for a
        party, or each companion is individually weaker. Decide it on paper before any number.
      - **S1 ROLES ON THE ONE COMPANION.** Add `role`, the role actions (heal the lowest ally, taunt,
        buff, revive an ally, ...) and a per-companion tactics focus, with NO slot change. Cheapest way to find out whether
        the actions are fun and legible in the log before multiplying them by five.
      - **S2 DATA MODEL.** `companion_party` (cap 5; slot 0 = beside the player), `active_companion`
        kept as an alias for slot 0. Audit every site that touches a companion: registered /
        `house_slot` (items 51 and its probes), corpse and death, trades, stable, fusion. Probe each.
      - **S3 COMBAT ENGINE.** Several companion actors per round with their own HP, threat and
        tactics. **THE SIMULATOR MUST MODEL THE COMPANION TEAM FIRST** - CLAUDE.md's rule: an
        instrument that does not play the game being shipped will certify the wrong curve with full
        confidence (the 2026-09-19 `refcal` finding). The reference player gains a companion team.
      - **S4 UI.** Companion cards in the right column (reuse the party member card), the beside-you
        card, a visible TACTICS button (a button, not a hotkey), and the shared-slot split in a party.
        Needs SCREENSHOTS - UI state is not reachable headless (memory
        `feedback_screenshot_before_theorising`).
      - **S5 ACQUISITION AND ECONOMY.** How a player ends up with role-diverse companions (eggs,
        stable, fusion, the species they hunt) and what the companions cost to keep. This is the same
        problem as the standing item "Real sinks for excess eggs and companions" and as 11(c)
        (companion variety) - decide them together, and let 11(c)'s rolled stats feed the roles.
      - **S6 CALIBRATION.** The reference party goes into `make_char`, then the whole chain ONCE
        (`-- preflight` first). Do not run the chain per slice; this arc is one batch.
      **PREREQUISITES AND SEQUENCING (my recommendation, owner to rule):** (1) the current unreleased
      work is large (this week's fixes, gold, auto-spend, the salvage and Temper changes) and the
      BALANCE BATCH (item 9) is still waiting on it - release it and run the chain on THAT build
      first, so the live game has a calibrated baseline and the death log starts measuring it; (2)
      start S0 in parallel, it needs no code; (3) the earlier "rework companion roles like the tank"
      the owner mentioned IS S1 - it is not a separate job; (4) item 11(c) and the egg/companion sink
      item belong in S5, not before it. **STILL OPEN for S0:** what a VARIANT may change about a role (tilt it, swap it, add a
      secondary); the exact TACTICS list per role (each role needs its own focuses - a Tank's "all
      out" is not a DPS's); whether the player can OVERRIDE a species' role (probably not); and the
      revive costs above.

### ⚑ PICK UP HERE — written 2026-09-19 for a gap of unknown length

**v0.9.833 is LIVE (client + server, hash-verified). Everything shipped is playable.**
**Player Phantoms is BUILT ON THE SERVER AND HELD BEHIND A FLAG.** Nothing about it is visible to
any player, and nothing breaks if it is never touched again.

---

#### 1. THE ONE THING TO DO FIRST

**Player Phantoms needs its CLIENT surfaces, and that is the whole remaining task.** Every server
handler exists and **nothing calls any of them**:

    list_prefab_posts    ->  a build-menu list of the three charters, with prices and what you hold
    buy_prefab_post      ->  spend Valor, receive the charter as an inventory item
    feed_phantom         ->  {kind: "egg", egg_id} or {kind: "companion", companion_id}
    enter_phantom        ->  descend, while standing inside your own post

Plus two messages the server SENDS that the client does not yet read:
`prefab_posts` (the charter list) and `phantom_state` (a post's investment, depth, and where the
certain egg falls).

**When all three surfaces work end to end, flip `PHANTOM_POSTS_ENABLED` in `server/server.gd`.**
That single constant is the entire hold, and it is checked at every door.

⚠ **THIS IS ALSO THE POINT WHERE IT STOPS BEING SAFE TO LEAVE HALF-DONE.** Today the feature is
genuinely inert. Once buttons exist, half-finished means a player can buy a charter and not place
it, or stock a post they cannot descend into. **Do all three surfaces in one sitting, or none.**

#### 2. WHAT IS ALREADY BUILT (server, held, each with a probe proven to fire)

    shared/prefab_posts.gd    3 Valor charters: 12k / 30k / 75k, 7x7 / 9x9 / 11x11
                              layouts GENERATED, so a wall cannot have a hole in it
    shared/phantom_model.gd   depth from distance, levels, species weights, reward curves
    persistence_manager.gd    get_post_investment / add_post_investment (ACCOUNT-owned)
    server.gd                 feed, descend, generation hooks, egg provenance
    character.gd              a hatched companion inherits `phantom_power`
    drop_tables.gd            companion_stat_mult = variant x provenance
    client.gd                 "(Phantom-born +N%)" on the companion display

    PROBES   a_held_feature_is_really_held
             the_phantom_pump_is_shut
             a_phantom_level_is_not_an_overworld_level
             the_phantom_reward_stays_inside_the_ceiling
             a_phantom_born_companion_is_stronger
             you_can_descend_into_your_own_phantom
    All seven PASS as of 2026-09-19, including `the_party_fights_together`.

#### 3. THE DECISIONS ALREADY MADE — do not re-litigate these

    1. DIFFICULTY   the Phantom picks its own LEVELS; the calibrated curve is untouched.
                    A monster generated at level N IS an ordinary level-N monster, so XP,
                    threat, post anchoring, the death log and quest targets are all correct
                    BY CONSTRUCTION. Audited across all five surfaces before any code.
    2. THE PUMP     gated by DEPTH AND SURVIVAL RISK and nothing else. Diminishing returns,
                    a lossy exchange and a cooldown were all offered and rejected.
                    ⚡ So volume must buy NOTHING depth does not also demand. Measured: an
                    absurd hoard pays 0.002 on floor 2 and 1.905 on floor 20.
    3. EGGS         a GUARANTEED egg at 70% depth, with quality as the variable part.
    4. OWNERSHIP    the ACCOUNT owns the post and its investment; what you carry OUT is
                    still lost on death.
    5. PROVENANCE   a phantom-born companion carries a multiplier the grade ladder knows
                    nothing about, capped at 1.35x = about ONE GRADE above its letter.
                    ⚡ Rank was a dead axis (1.26x across a whole tier, and `power_index`
                    already clamps above RANKS). Tier collides with the letter. This rides
                    alongside both.

#### 4. STILL OPEN IN THE PHANTOM DESIGN (from the 2026-09-02 archive)

    * valid PLACEMENT area for a charter - min distance from existing posts, terrain rules
    * whether a Phantom is per-post / per-account / shared, and who else may enter
    * reward gating: enough to gear a fresh character locally, without becoming the best
      farm in the game for an established one

#### 5. EVERYTHING ELSE

**Waiting on TIME, not work:** re-run `tools/death_log_audit.py` against the 1.81%
deaths-per-encounter baseline. ⚡ That baseline predates the 2026-09-19 batch AND the party-death
fix, so it measures the whole batch together and the instrument itself changed - party deaths used
to be recorded EMPTY and the audit read those blanks as one-shots at parity. **The balance batch
stays parked until that data lands.**

**Before proposing anything: `python tools/backlog_audit.py`.**
**Before committing any .gd: `bash tools/gdcheck.sh <files>`** - `--check-only` prints its error and
exits 0, so a pipe silently swallows it. That wrapper caught two invented functions on 2026-09-19.

### ✅ THE TUTORIAL SKIP AND THE HELP POP-UPS (2026-09-19)

Owner: *"The original tutorial should be skippable and players should also be able to disable the
help popups for their account if they want."*

**Both were already built - and one of them only worked in one direction.**

  * the walkthrough has a **Skip** button on its opening prompt (`_skip_tutorial`) ✅
  * the pop-ups have an **account-level** opt-out, persisted server-side ✅
  * ⚡ **turning them back on was impossible.** The opt-out lives on the pop-up itself, the
    setting lives on the ACCOUNT, the server never reported its value, and Settings had no row
    for it - while the line the pop-up printed on its way out said *"Turn them back on in
    Settings."* A promise with nothing behind it.

**Fixed:** the server reports `tutorials_state` (on character select and after any change), and
Settings > Game gained **[9] Help Pop-ups (this account)**. Added at the END deliberately: every
other row is addressed by its number, so inserting above one would move the keys under the
player's fingers.

⛑ **TWO SETTINGS THAT SOUND ALIKE, AND MUST STAY SEPARATE** - conflating them is what hid this:

    disable_tutorial    CLIENT, per install   is a NEW CHARACTER offered the walkthrough?  [5]
    tutorials_enabled   ACCOUNT, server-side  do the first-touch teaching pop-ups appear?  [9]

Probe: `the_help_popups_can_be_turned_back_on.gd`, which also asserts the other rows did not
renumber and that the two settings are still distinct.

### ⚑ WHERE THINGS STAND — end of 2026-09-19

**v0.9.831 is LIVE, client and server, hash-verified. NOTHING is built-but-unreleased.**

**PARTY PLAY SLICE 1 SHIPPED.** Everyone walks their own path; whoever meets a monster pulls the
party in within `PARTY_PULL_RADIUS` (8). The race resolved itself - see the DQIX item. Slices 2
(map indicator + run-in join), 3 (travel rules / Muster Sigil) and 4 (dungeons follow the
overworld, owner direction) are named there with their prerequisites.

**THE POST-COMBAT UI ARC IS CLOSED** (v0.9.826-831), from one report of "a flash". It was five
distinct faults, and the useful record is how they were found:

    826  the sprite overlay awaited a frame for a layout Godot 4.7 no longer defers
    828  the map was drawn into the HIDDEN column during a fight, then relocated
    829  margins/frame positioned for the WIDER combat canvas - nothing in 56k lines
         had ever listened for a `resized` signal (so window resizes had it too)
    830  my own 828 regression (restore ran after the text took the canvas), plus the
         map composed at the combat width and re-sizing a second later
    831  the FIRST fight of a session had nothing cached to redraw, and no way to ask

⚡ **I GUESSED TWICE FROM THE CODE AND WAS WRONG BOTH TIMES.** Three owner screenshots produced
three different real causes. For anything VISUAL, ask for a screenshot before theorising - the
headless instruments cannot reach the state, and `--uimeasure` runs at the login screen with no
combat panel at all. One measurement that could not reach its target was deleted for that reason.

**Two things are WAITING ON TIME, not on work:**

1. **⚑ NOW DUE (2026-10-13, 24 days on): re-run `tools/death_log_audit.py`** against the 1.81% deaths-per-encounter
   baseline. ⚡ That baseline predates this whole batch, so it measures everything together -
   and it is now cleaner than it was, because party deaths used to be recorded EMPTY and the
   audit read those blanks as one-shots at parity.
2. **The BALANCE BATCH stays parked** until that data lands.

**Before proposing anything, run `python tools/backlog_audit.py`.**

### ✅ v0.9.816 — THE CHAIN WAS MEASURING A GAME NOBODY PLAYS (2026-09-19, LIVE)

Started from one owner question — *"are we sure the sim is using the actual starting decks each
class is using?"* The decks were fine. Everything behind them was not. **Four instrument faults,
each hiding the next**, all in the machinery that sizes every monster in the game:

1. **Gear rarity sampled the DROP table once per slot** — models a player who has already found a
   suitable item for all seven. Live L1-4 characters wear **87% common**; the model made 57%.
   Fixed with `LOW_LEVEL_WEAR`, which converts the drop distribution into the measured *wearing*
   distribution below L15.
2. **`average` handed CLASS KIT to level-2 reference players** — gear that drops only from Hoarder
   monsters (Minotaur / Wraith / Mimic). Live L1-9 gear is item level 1.2-2.9 with none of it.
   Gated to L15+.
3. **The curve-writing sampler fled every losing fight**, so `refcal` reported 0.0% death at every
   level while the live log held 50 real deaths. `run_fight` had been fixed; `_fight_stats_at`,
   the one that writes the curve, had not. One value, two places.
4. **`refcal` verified a curve it does not write.** `_load_reference_curve()` bails on
   `if not _reference_anchors.is_empty(): return`, and `_inject_curve` fills that array on pass 1 —
   so `species_power` and `role_multipliers` were **never read for the whole run**. It fitted and
   self-verified without them, then wrote a file preserving them: L10 verified at 85% and measured
   63% everywhere else. **Long-standing** — the WRITE side was fixed when species_power was found
   to be wiped; the READ side never was.
5. **The monotonic clamp ran on the BASE curve**, discarding the calibrator's own corrections
   (L5 `str` 18 -> 54, L10 27 -> 54) — the documented smoothing bug's other half. Now clamped on
   the **effective** curve (base x mean species multiplier at that level), so a base dip that
   compensates for a multiplier spike survives while a genuine dip is still repaired.

Together these made the simulated L1-10 player win **~100%** of fights, so the chain kept
strengthening monsters to compensate. Faults 4 and 5 were in the curve that was live until now.

**Result:** every anchor within ±11pp of target (only L5 exceeds ±10, at -11), death 0.9-6.8%,
risk FALLS with progression again. The L50-L1000 band moved from 40-47pp too hard to on-target.
`refcal`'s verify now agrees with independent reads to 1-4pp where it had been 20-49pp adrift.

**The durable gain: deaths per encounter is now an EXTERNAL target.** Every character records
`monsters_killed` whether it lived or died, so the live server can report **50 deaths / 2766
encounters = 1.81%** (an upper bound — a successful flee is neither). `flee_rate_matches_live.gd`
fits the flee model to it. The chain finally answers to something outside itself.

**Four claims retracted this session, all the same error — a numerator without its denominator:**
monsters at 3.8x the curve (really **1.4x**); deaths at L1-9 meaning early game is over-tuned
(**83% of living characters are there too**); `refcal` targeting a flat 60% (there is a ramp,
92% -> 58%); and my own flee "fix" (1/44, from a deaths-only sample that cannot contain a
successful flee — it made death **nine times worse** than the model it replaced).

Also landed: **preflight check `[4]`** (the injected world must carry what the file holds —
deterministic, proven to fire by reverting the fix), a **CLAUDE.md rule** (*two paths agreeing is
not verification when they share state; verify against the artifact*), and **L3/L5 rows in
`DIFFICULTY_RAMP`** so the band holding 83% of players has its own knob (values exactly neutral —
verified no target moved).

### ✅ MERCHANTS ARE FIXED AND LIVE (2026-09-19)

Owner: *"I didn't see any last time I was on the live server."* They were working the whole time —
the live log is full of them hauling stock — and **invisible while doing it**.
`_refresh_merchant_cache` dropped any merchant resting at a post with a bare `continue`, so it did
not draw, `is_merchant_at` was false and `get_merchant_at` returned nothing. Standing at a post you
met one **0% of the time**, at any road length; walking a road, 5-18%.

Now parked on the first road tile **outside** the post (the post centre is where the station art
sits). Probe `merchant_is_findable.gd`, proven to fire.

**DEPLOYED with the v0.9.820 server swap** (hash-verified `d06e1e7beab6549c`). This was
server-side map generation, so it needed the deploy rather than a client release to reach anyone.

**ANSWERED 2026-09-19 - the wagon stays.** Owner, shown the sprite: *"Merchant can be a wagon."* The original ask was "NPC sprites instead of symbols", and it was never a `$` (that is only the ASCII fallback); the only open part was whether a trade wagon or a driver was wanted, and it is the wagon. Nothing further on merchants.

### ⚑ BRACE — the defensive floor, and what it unblocks (2026-09-19)

Owner approved after the boss-telegraph proposal was measured and found unworkable: *"If they don't
draw the card they need that round how can they do so?"* They could not.

    class                       hard answers in deck   P(one in a 3-card hand)
    Sage                                           3                     100%
    Fighter / Sorcerer                             2                      90%
    Barbarian / Paladin / Wizard                   1                      60%
    Ninja / Ranger / Grifter                       0                       0%

The whole Trickster archetype holds nothing in `DEFENSIVE_REPRIEVE_ABILITIES`, and combat's
always-available actions were Attack / Use Item / Flee. So "telegraphed but answerable" would have
been unanswerable 40% of the time for half the roster and always for a Ninja.

**SHIPPED:** an always-available combat action, named per archetype at the owner's request —
**Brace** (warrior) / **Ward** (mage) / **Slip** (trickster). 40% damage reduction, one round,
free, costs the turn, no defensive reprieve — deliberately below `iron_skin` (60% / 4 rounds /
costs a card) so the cards stay worth holding. It lives in the inert slot that was held open for
Outsmart, so no card shifts a key. Probe: `every_class_can_answer.gd`.

- [ ] **THE REMAINING 24 cyclical bursts still land the moment the counter hits.** (The five that DO telegraph were carried through the 2026-09-19 chain run.) The probe's
      section 4 lists them by name every run, so this is a visible queue rather than a silent gap:
      `void_step`, `iron_discipline`, `soul_siphon`, `contagion_aura`, `lullaby`, `wind_shear`,
      `sonic_echo`, `hatchling_swarm`, `infernal_curse`, `triple_threat`, `three_heads`,
      `soul_forge`, `dragons_hoard`, `element_cycle`, `riddle_curse`, `primordial_roar`,
      `coil_squeeze`, `death_mark`, `madness_aura`, `temporal_rewind`, `chaotic_surge`,
      `divine_punishment`, `decay`. Converting each is now a data change plus a call - the
      mechanism is built and proven. **Not all of them SHOULD convert**: an aura or a persistent
      debuff is not a burst, and telegraphing everything would make every boss the same metronome.
      Judge each against "is this a single big moment the player could answer?"


### ⚑ OPEN QUESTIONS FROM THE BALANCE PASS — ranked

1. **~~`species_power` has NEVER weakened a species.~~ ANSWERED AND FIXED 2026-09-19.** The cause
   was not the clamp - it was that **speciescal's two samplers modelled different players**.
   `_species_win_at` sampled Fighter / Wizard / Grifter (the strongest of their archetypes, which
   `_fight_stats_at` had already been fixed away from for that reason) and **never retreated**,
   while the mix it is compared against samples all nine and flees at 30% HP. Measured on
   identical monsters at identical levels: **+24pp at L5, +12pp at L10, +18pp at L50**. Every
   species was judged against a weaker yardstick than itself, so every species measured "too easy"
   and was strengthened, and 68 of 136 corrections pinned at the ceiling.
   The comment licensing the shorthand said the other users are "read-only and their bias only
   colours a report" - `_species_win_at` is not read-only, it writes `species_power`. That note is
   corrected in place.
   Both samplers now share a player model; worst residual gap **4pp**, inside sampling noise.
   Probe: `speciescal_compares_like_with_like.gd`.
   **The curve on live was fitted through the biased sampler**, so `species_power` is wrong until
   the next chain run - which should NOT happen yet (see 3). Raising the clamp would have
   amplified the bias, which is why it was worth measuring before touching.
2. **(retired) `species_power` one-sidedness** - Every correction it makes is a strengthening:
   minimum x1.05, median 2.47, 68 of 136 corrections pinned at the x2.50 ceiling, **zero below
   1.0**. A calibrator comparing each species against its own mix should land on both sides of 1.0
   roughly evenly. **Do NOT widen the clamp to "fix" this** — a wider range on a one-sided
   comparison amplifies the bias. The question is why the comparison is one-sided.
   *A ratchet hypothesis (mix carries the previous run's multipliers while each candidate is
   measured raw) was TESTED and did not hold: clearing the multipliers barely moves the L50/L250
   mix, because the species carrying big multipliers are high-tier and do not spawn there.*
   `species_power` does reach real monsters — Balrog at L50 is 13,073 HP with it, 5,089 without.
2. **L5 sits at 79% win against a 90% target** — the one anchor outside ±10pp. Two honest routes:
   lower the target to meet reality (it is a `DIFFICULTY_RAMP` row now), or fix the fit, which is
   (1). **Do not touch until live data says whether L5 actually plays rough.**
3. **Let the live data close the loop before changing anything else in combat.** Every monster in
   the game just moved. Deaths per encounter is now measurable; re-run `tools/death_log_audit.py`
   after a week of play and compare against the 1.81% baseline. Stacking another balance change
   now destroys attribution — this is the first time the loop can actually close.


### ✅ REST AFTER THE BOSS — v0.9.810 (2026-09-18)

Owner: *"After killing the boss of a dungeon it looks like you can't rest anymore as the option
isn't on the bar anymore."*

**The branch's own comment said `Items + Rest still available` and the array under it offered Items
and eight blanks.** A comment describing an intention nobody implemented reads as documentation and
tests as nothing. It is also the worst state to lose Rest in: it sits between the boss fight and the
walk to the final chest, and in-dungeon recovery is half the overworld rate.

`tools/probe/dungeon_bar_never_strands_you.gd` walks every action-bar state guarded by
`dungeon_mode`, exempting by NAME the four that are modals rather than places you stand
(trap acknowledgement, pending continue, the food picker inside Rest, the resource prompt), and
fails if any remaining state omits Rest or Items. Proven to fire by removing the button again.

### ✅ THE REST OF THE CARD NUMBERS — v0.9.809 (2026-09-18)

Owner named Frost Nova and Forcefield and added *"some of the other card numbers aren't matching
either."* Sweeping the remaining faces against the casts found two more, both the same shape.

- **Arcane Surge** — face said `+20 + INT/5 % "spd"`; the cast grants `40 + INT/4` percent **spell
  damage** and a 25% double-cast. Half the number, and a stat the ability stopped granting when it
  was renamed. The hover description was already right.
- **Assassinate vs the Read gauge** — *"Gauge says Assassinate ~50/5% and card face says ~49 4%
  kill."* **Neither was wrong.** Assassinate is variable-cost (ceiling 34, 44% of the pool), so the
  face quotes what THIS cast commits — the rule the owner set on Magic Bolt — while the meter note
  is built server-side with no client to ask and quotes a full spend. The meter re-formats its
  numbers against the planned spend and keeps the server's wording, because only the Ninja's
  finisher is a roll and a client copy of that distinction is what drifted last time.

**The headline number is structurally safe**: `_estimate_ability_card_effect` prefers the server's
`preview_ability_effect`, `_ability_card_estimate` parses it back for the description (and now
understands `Shield N` as well as damage and healing), and `tools/probe/preview_drift.gd` checks
that source against real casts.

**▶ FILED, not guessed at: the SECONDARY figures have no shared source by construction.** A buff
card's stun chance, per-round bleed, and durations are a local formula in `client.gd` sitting beside
the real one in `combat_manager`, because `preview_ability_effect` returns ONE headline number. That
is what let Arcane Surge drift. The fix is to widen the server preview to carry a card's secondary
figures; a first attempt at a *diffing tool* was written and thrown away because it reported 11 of
14 abilities and was mostly comment prose and BBCode colours — CLAUDE.md's own note on the
adjacent-tile advisory says what that costs.

### ✅ THE FOURTH DEAD LINK — v0.9.808 (2026-09-18)

Owner: *"Hovering the underlined text in death log still doesn't work."*

**It never could, and it was not the death log.** `_ow_side_place` is the pinned label every PAGE
in the side column is drawn into — the death screen among them — and it was built without
`meta_hover_started`, `meta_hover_ended` or `meta_clicked`. A `[url=...]` underlines itself whether
or not anything listens, so an unwired label is visually identical to a working one.

**That is the fourth time**, and the previous three are all recorded in `client.gd`'s own comments:
the battle panel's damage numbers (*"the damage in the party combat log still isn't hoverable"*),
the dungeon key's tiles (underlined and dead for a week), and `map_display.meta_clicked`, which was
never connected so click-to-inspect died with the sprite overlay while hovering kept working.

All three column labels are wired now. `tools/probe/every_link_label_is_wired.gd` asserts the six
named surfaces and then lists every `RichTextLabel` the client builds with bbcode and whether
anything listens to it — 14 built, 10 silent, which is the list to check the next time a player
says an underline does nothing.

### ✅ A CHOICE IS NEVER TEXT — v0.9.815 (2026-09-18). THE REAL FIX FOR THE CLASS.

Owner, on the third instance of one symptom in one evening: *"Scroll of finding still flashes on
the left side of the screen behind the map then the map takes it back over and the player can't see
to select anything. Why are we not fixing these properly? When we find the proper solution to this
we need to fix it so it can never happen again."*

**⛑ THREE PER-SITE FIXES FAILED, AND THE CODE ALREADY SAID THEY WOULD.** `_ow_text_in_column()`
carries this note, written months ago: *"There are 230 such clears in this file, so guarding them
one at a time was never going to hold."* `display_game` routes text three ways off LIVE STATE —
does the map own the canvas, is a panel open, has a page claimed it — and

```gdscript
return _ow_canvas_eligible() and _ow_canvas_showing and not _canvas_panel_open() and not _ow_wide_page
```

**a Scroll of Finding is used FROM THE INVENTORY, so `_canvas_panel_open()` is still true that
frame.** The prompt goes to the canvas instead of the column, and the map repaints over it. Adding
`_page_clear()` changed nothing, because the clear decides WHEN a page starts and not WHERE it
lives. I made that exact mistake, having read that exact note.

**THE RULE IS STRUCTURAL NOW.** A flow the game is *waiting on* draws in a Control above the map:
`client/choice_panel.gd`. A Control has no routing decision to get wrong, nothing that can repaint
it, and no state in which it is invisible while the game waits. One modal serves every such flow,
so there is nothing to keep in step.

| | |
|---|---|
| routed through it | Scroll of Finding, Scroll of Summoning (out of combat; the in-combat picker already worked) |
| owns keys | 1-9 pick, Escape / Space / Enter cancel — and the `_process` pollers **stand down** while it is up, or one press fires twice |
| height | scrolls under a ceiling — measured, **40 options fit 73→646 on a 720px screen** |

`tools/probe/a_choice_is_never_text.gd` asserts the wiring, that every waiting flow opens the modal
AND closes it on both exits, that no poller reads the same keys underneath it, and then EXECUTES
the panel: shows it, measures a 40-option list against a 720px screen, presses `3` and presses
Escape.

⛑ **And the probe's own first run was wrong in a way worth recording:** it reported the panel
ignoring every key press. GDScript lambdas capture a local by VALUE, so `func(i): got_index = i`
assigned the closure's copy and the outer variable never moved. The harness could not see the
result it was asserting. Captured in an Array now.

**▶ NEXT, and the owner has not been asked yet:** the remaining numbered-choice flows are still
text — home stone options, companion release/selection, trade item/egg/companion pickers, unequip.
They are not currently *broken* (they claim pages and their callers clear), but they are the same
shape and the modal exists now. Converting them is mechanical and would retire the class outright.

### ✅ MENU PLACEMENT SWEEP — v0.9.807 (2026-09-18)

Owner, after a Scroll of Finding printed its choices where they were immediately painted over:
*"We really need to do a thorough sweep to fix this across the board for all menus and items."*

**Measured before fixing.** `display_game` routes text three ways — the dungeon run log, the
overworld side column, or the canvas — and the choice depends on whether a page currently OWNS the
canvas. `_page_clear()` is what claims it. A screen that prints without claiming is placed by
whatever happened to close a moment earlier, which is why this depends on where you opened it from.

`tools/prompt_surface_audit.py` walks every function that renders a screen the player must answer:

| | |
|---|---|
| prompt-shaped functions | **74** |
| already claimed a page | 50 |
| drawn BY a page that claims (every caller clears) | 24 |
| placed by whatever closed last | **11 → 0** |

The first run said 35, because it counted sub-renderers like `_display_trade_items_tab` that are
only ever reached from a page that clears. Following callers one level is what made the number
worth acting on. Fixed: merchant shop, upgrade list, unequip page, item details (both the inventory
and the shop copy), tutorial steps, the combat item text fallback, and both scrolls. The tool exits
non-zero, so it can go in the release gate when convenient.

### ✅ THE TUTORIAL HINT HAS A CEILING NOW — v0.9.807

Owner: *"Companion screen is too long vertically AGAIN, I can't even see the button to click at the
bottom."* **"Again" is the finding.** `fit_content` with no cap makes the panel exactly as tall as
its text, and a `CenterContainer` then centres it — so a long hint overflows at BOTH ends. Every
previous round shortened the TEXT; text grows back. The body scrolls under a ceiling now, and the
panel claims its own rect (a `top_level` Control has no parent rect, so `PRESET_FULL_RECT` resolved
to zero and the overlay was pinned top-left rather than centred — the second half of what was in
the screenshot). `tools/probe/hint_panel_fits_the_screen.gd` builds it with a body four times the
longest hint the game sends and measures where the button lands: it failed at 1327px with the button
at y=1573 on a 720px screen, and passes at 583px with the button at 601.

### ✅ LIVE-PLAY REPORT BATCH — 2026-09-18 evening (11 reports, all fixed)

The owner played the v0.9.805 build and reported eleven faults in quick succession. Each was
traced to a CAUSE rather than patched where it showed, and most of the causes turned out to be
shared with something else on this list.

| # | reported | cause | fix |
|---|---|---|---|
| 1 | Warden Hollis standing on the quest board | `_place_stations` guaranteed only that no two stations are CARDINALLY adjacent, while the map draws art up to 3x3 — nine tiles reach past the one cell the rule protects | station placement is FOOTPRINT-aware; the baker writes `shared/station_art_footprint.gd`, read by both the placer and the renderer |
| 2 | Enchanting table is "a piece of another sprite" | the spec took column 1 of a TWO-column desk, sawing the book and the desk in half | `craft_stations (7,0) 2x2` — the whole desk |
| 3 | post centre is "a big 3x3 blue thing", then "the half sword sprite" when you walk away | TWO faults: the 3x3 is a hanging WALL BANNER, and the sword means the previous bake **never reached the build** | fountain (`sun_city 22,4`), plus an art-freshness gate (below) |
| 4 | healer's art still changes, "different if I bump into it from different sides" | `_post_npc_art_seed` hashed `current_post_name` — **a field nothing has ever written** — so it always fell through to the PLAYER's x,y | the server sends the post's own coordinates; probe executes it from 2,880 standing positions |
| 5 | "I still don't understand how to put in a commission… Locked Stone Wall (Lv3), I can't click it" | both client and server admitted `specialist_only` recipes ONLY, so a recipe above your SKILL — the commonest reason to want help — was refused | posting a job works on anything you cannot make; locked rows are clickable; the first-time hint now fires |
| 6 | panels close with X or Escape, others with Space | of 31 panel scripts, 8 took Escape only, 3 took Space, the rest closed via the action bar | one `client/panel_close_keys.gd`; ten panels route through it and say so on the button |
| 7 | Cataclysm says "Ramp Focus first"; the Sorcerer has no Focus | the Meteor branch typed the literal while the Devastate branch two blocks above used `_momentum_name` | reads the meter's own label |
| 8 | Frost Nova 42 on the card, 50 on hover; Forcefield the same | the description arms re-derived their own figures; the shield case had no shared source at all because the parser only understood damage and healing | every headline number comes from `_ability_card_estimate`, which prefers the SERVER's quote |
| 9 | "Chaos bolt shows as Magic bolt in the combat log" | `ability_line(…, "title", "Magic Bolt")` fell back to the literal at the call site | a `title` falls back to the class's own name, keeping the template's decoration |
| 10 | Quest board → Dungeons → Quests says "You have no active quests" | the tab always asked for the quest LOG; the Escape path already made this distinction and the tab did not | the tab returns to the view you came from |
| 11 | "the warden doesn't go around hotzones" | a hotzone does not BLOCK movement, so `move_player` — deliberately the only authority on what blocks a step — says yes, and shortest-path walks a level-1 through the worst ground on the map | the escort prefers hotzone-free ground, with a fallback so a route is never lost. Measured: 3 of 4 dangerous routes diverted, **+0.0 tiles** average detour |

**And one that was not reported as art at all.** Report 3's second half — *"still going back to the
sword sprite"* — is a sprite this repo replaced in a commit that is an **ancestor of the released
tag**. The PNG was right on disk and right in git; the build drew the old one, because Godot only
re-imports on an editor pass and **the release gate had never looked at a pixel**. `overworld_art=true`
(one file exists) and `big_tiles=20` (a manifest has rows) are both true of a build carrying every
tile from a month ago — the ingredients, not the function. The baker now writes
`shared/overworld_art_fingerprint.gd` and `--buildverify` recomputes it from the **packed** textures;
the gate fails on any mismatch.

**Also fixed while in there:** a threat-relief bounty was a `DUNGEON_CLEAR`, so accepting one built
a PERSONAL dungeon "25-40 tiles from the player" — which is exactly the 38 tiles the owner measured
when the board had advertised 70 west. Its own text promises *"completing this clears the post's
Under Threat state"*, which clearing a private copy cannot do, so the reward was **unreachable**,
not merely mislabelled. It binds the real threatening instance now, and a shared world dungeon is
never erased on one player's turn-in.

**New probes (all proven to fire):** `post_art_does_not_cover_people`, `post_npc_art_is_stable`,
`card_is_called_one_thing`, `panels_close_the_same_way`, `escort_walks_around_danger`.

**Open, owner's call:** the post-centre fountain was baked as the recommendation without a pick —
`tools/tile_region_sheet.py post_marker` re-renders the alternatives, and it is one line in `CUTS`.


### ✅ COMBAT LOG REWORK — SHIPPED v0.9.803 (2026-09-18)

Owner: *"start the combat log rework. Once we get it right we can cut a new release."* Four rounds
of live testing; every item below was reported from play and confirmed fixed from play.

**The shape.** One SUMMARISED line per actor per round, built from the server's own `dmg` /
`taken` / `ability` metadata rather than by joining prose. Measured first: a three-round solo fight
emitted 12 lines, the worst two at **294 and 311 characters**, which wrapped to five or six rows
each - so the fold that already existed was trading line COUNT for line LENGTH and gaining nothing.
Each line carries its blow-by-blow as hover text, so nothing is lost.

**Round 1 — rendering**

**Round 2 — attribution and reachability**

**Round 3 — the log becomes a panel**

**Round 4 — the last two**

### ⛑ WHEN THE HARNESS PROTECTS ITS SUBJECT, IT CAN DELETE THE QUANTITY BEING MEASURED

The `combat` shots scene godmodes the character so a capture cannot lose its own subject. Correct
for a screenshot; useless for *"how much damage did the player take"*, which godmode makes zero by
construction. Run to check the missing damage number, it reported `taken=0` for a reason with
nothing to do with the code under test. The second attempt used a monster eight levels down, which
missed twice and was shielded once - nothing reached HP, so zero was **correct**. A reading that is
right for the wrong reason is indistinguishable from the bug.

`logmeta` is the scene that can see it: no godmode, a same-level monster, and the player's HP
printed beside every line so `taken=0` is readable rather than ambiguous.

### ▶ OPEN AFTER v0.9.803 — START HERE NEXT SESSION

1. ~~**The curve is stale for Ethereal fights.**~~ **CLOSED by owner decision, 2026-09-18.** The
   companion now acts through an ethereal dodge, which is technically a player-power change and so
   would normally invalidate `reference_monster_curve.json`. Owner: *"I'm fine with ethereal fights,
   I don't think its enough of a change to worry about player-power from."* Recorded rather than
   deleted, because the standing rule is real and the next person to read it should see that this
   was an explicit waiver for a narrow case (Ethereal monsters, 33% of attacks), not an oversight.
2. **F12 does not fire while a combat line is hovered** (owner, 2026-09-18). Not reproduced and not
   explained: nothing in the hover path touches key input and the hover popup is a plain
   `PanelContainer`, not a window that can take focus. Rather than a third guess, the handler now
   logs every request AND every debounce - the client log will say whether the key arrived.
   *Owner reported it working again in round 4, so it may be intermittent.*
3. **The first line of a fight renders unsummarised.** Cosmetic, one line per fight. Owner's
   Harpy screenshot shows `▸ Harpy 3 hits` (summarised) followed by `The Harpy attacks but
   misses!` (raw green prose) in the same round.
   **Narrowed 2026-09-18, and the obvious suspects are both cleared:** `_push_first_strike_to_log`
   DOES tag its lines `"monster"`, and the `combat_start` narration goes to `display_game`, which
   is `game_output` - hidden behind the battle scene during a fight - not the log band. So neither
   is the source. Not reproduced: two `logmeta` runs emitted no untagged line at all, so it needs
   a fight with the specific shape (monster wins initiative, ambusher, or a summoner/Blinding
   monster like the Harpy). **Get a repro before theorising further** - three plausible causes have
   already been eliminated by reading, which is the point at which reading stops paying.
4. ~~**Threat quest rewards.**~~ **DONE 2026-09-18.** Owner: they *"don't seem to scale and is
   low rewards."* Both halves were true and they were one cause: the reward was a flat lookup on
   the dungeon TYPE, so a threat at a level-200 post paid what the same type paid outside Haven,
   while every other quest on that board had already been re-anchored to the land.
   Now anchored on the POST's area level - the same quantity `_scale_quest_rewards` uses - with the
   tier table demoted to what it always was, a weight for how serious that kind of dungeon is.
   Anchored on the post and not the dungeon INSTANCE deliberately: the pricing runs twice for one
   quest (offer, then rehydrate from a quest id that encodes post + type only), so the instance is
   unknowable the second time. That constraint is what made the original flat - it rules out the
   instance, not the land.
   **Sized against a target, not a number that looked big.** Measured against the MEDIAN dungeon
   quest on the same board (the median, not the best - a board carries seven of wildly different
   sizes): it was 0.64x median XP at Haven collapsing to **0.06x** at Northwatch. Now 1.14x / 0.94x
   / 0.83x across the same three posts, valor 2.29x / 1.12x / 1.00x. It can only ever raise a
   bounty - the old table is a floor.
   **The first attempt was wrong and the measurement is what said so:** it borrowed
   `QUEST_XP_REANCHOR_CAP`, which bounds a re-anchor above an already level-scaled base, and
   applied it to a flat one - freezing the payout at 4,000 XP for both a level-28 and a level-37
   post. That passed every check written at the time, because none of them compared it to the
   board. `tools/probe/threat_quest_rewards.gd` now does, and asserts the band.
5. **Balance work is BATCHED. See the queue below.** Owner, 2026-09-18: *"We should hold on the
   balance items until we have a batch of things that need looked at so we don't have to run it a
   bunch of times, taking a lot of time."*

### ⚑ A DESKTOP BALANCE TOOL — owner direction 2026-09-18. FILED, not started.

*"We may want to build an external tool that I can run from my PC to tune monster difficulty, item
effectiveness, etc. A tool that lets me make big balance changes and fine-tune combat, rewards,
loot drops, card multipliers etc, in other words an exhaustive tool that's easy to use and can make
changes to the live server as needed. Those changes would need to be able to be saved and
templatable as well."*

**⛑ MEASURED BEFORE PROPOSING ANYTHING, because the answer decides the whole shape:**

| where the knobs live | count |
|---|---|
| already data in `server/balance_config.json` | **90** |
| `const` in GDScript — needs an export + redeploy | **101** |

Broken down: `combat_manager.gd` 48, `character.gd` 25, `monster_database.gd` 15,
`drop_tables.gd` 11, `card_gear.gd` 2. And `set_balance_config()` is called **once at startup** —
there is no reload path, so even the 90 that ARE data cannot change without a restart today.

**So slightly more than half of what the owner wants to tune cannot be tuned at all right now.**
A UI built over today's surface would be a UI over 47% of the game.

**Three pieces, in this order. The first is not the UI:**

1. **Migrate the knobs into data.** Each `const` moves to `balance_config.json` with the current
   constant as its default, read through the config with the constant as fallback. Mechanical,
   and nothing else works without it. Do it in batches by file so each batch is reviewable.
2. **Hot reload + apply.** The server re-reads the config on a signal (the same sentinel shape
   `pending_shutdown.txt` already uses) so a change lands without disconnecting anyone.
3. **The desktop tool.** Grouped controls over the merged schema, named profiles saved as JSON
   templates, diff-against-live, push, revert.

**⛑ AND A FOURTH THAT THIS SESSION ARGUES FOR HARD: the tool must show LIVE OUTCOMES beside each
knob.** Tuning against the simulator is what produced a curve reporting **0.0% death at levels 1-5**
while the live server recorded **40 deaths in that band in two weeks**. `tools/death_log_audit.py`
already computes deaths per band, per class normalised by population, rounds-to-death, monster-trait
share and gear relevance — that is the panel the tool needs, and it exists.

**Sequencing:** after the retreat-model fix below, because a tool that tunes against a broken
instrument is worse than no tool.

### ⚡ THE DEATH-RATE BASELINE IS A PRE-CHANGE NUMBER — do not read it as a clean before/after

Owner 2026-09-19: *"It will take a couple of weeks before we have useful data from players."*

That retires the plan of freezing combat work to protect the measurement - two weeks is far too
long a freeze, and it was costing more than the measurement is worth. The batch below gets run.

⛑ **BUT THE COMPARISON IS NOW CONFOUNDED, AND THAT HAS TO BE WRITTEN DOWN.** The
**1.81% deaths per encounter** measured on 2026-09-19 (50 deaths / 2766 encounters, from
`monsters_killed` across living and dead characters) is a **v0.9.816-and-earlier** number. Running
the chain over this batch means the next two weeks of play measure a DIFFERENT game. So:

* comparing the two in a fortnight measures **the curve refit AND the batch together**
* it is still worth doing - the direction tells us plenty - but nobody should report it as
  "the v0.9.816 curve delivered X"
* re-measure with `python tools/death_log_audit.py`; the baseline to quote alongside is 1.81%,
  **labelled as pre-batch**

### ⛑ THE BALANCE BATCH — add here, run the chain ONCE

**Do not run the calibration chain for a single item.** It is ~25 minutes, it is one-pass-each by
design (see CLAUDE.md: iterating means two layers control the same quantity), and every player-side
change between one run and the next makes the previous run stale anyway. So player-power changes
and balance questions accumulate HERE, and the chain runs once over the batch.

**The rule for adding:** anything that moves player power, monster power, or a reward that is sized
against either. Write what changed and what it should be measured against - a line saying only
"check balance" is not usable a week later.

**Before running anything**, `preflight` (2 min) - it asserts what the chain assumes and cannot
check itself. Then `speciescal` → `refcal` → `rolecal`, one pass each, in that order.

Currently queued:



- [ ] **Same-level death rates.** P60 Wizard measured **31% death at its own level** against a
      ~0.3% target, by two agreeing read-only audits (2026-09-13). The chain steers by WIN rate and
      is structurally blind to deaths, so this cannot be fixed by running it - it needs a
      per-class look first. **The largest item in the queue and the reason the queue exists.**
- [→] **Threat bounty rewards were re-anchored** (v0.9.803) — **A WATCH NOTE, not work.** Nothing
      is unbuilt here; it asks that the band be re-measured if the quest curve moves, and names the
      probe to do it with. Marked so it stops counting as a task. Not player power, but a reward sized
      against the board: now 0.83-1.14x the median dungeon quest where it was 0.06-0.64x. If the
      quest curve moves, re-measure with `tools/probe/threat_quest_rewards.gd`.
- [→] **Realm-wide valor economy pass — DUPLICATE.** The live entry is "THE VALOR ECONOMY,
      REALM-WIDE" further down; this copy exists only so the batch reads complete. Do not work
      from this line. ~~written up in full at "THE VALOR ECONOMY, REALM-WIDE"**
      further down this file; that is the source of truth and step 1 is already part-done. Listed
      here only so the batch is complete. It is NOT a chain item - the chain sizes combat, and this
      sizes prices - but it shares the batch's reason for existing: `QUEST_VALOR_PER_LEVEL := 3.5`
      is an interim anchor calibrated against sinks the owner has already said are wrong, so any
      valor number tuned before it lands is tuned against a moving target.
- [→] **Forcefield's 3-6x nerf still wants a live feel check** (from the 2026-09-02 balance day). <!-- audited: 2026-09-19 --> Re-marked: a FEEL CHECK for the owner, not work.
- [→] **Are any of the 53 dungeon cards worth a deck slot? — DUPLICATE.** Same question as
      "Dungeon card pass — the POWER half" in Phase 4, which is the live entry. Kept only so the
      balance batch reads complete; do not work from this line. (Found 2026-09-19: the two open
      differently so a title match missed them.) The COVERAGE half shipped - all 53
      exist, themed and sized - but the owner's actual bar was *"cards that classes may want to
      swap into their decks"*, and nothing has measured whether one clears it. The question is:
      for each class, does substituting a dungeon card for its weakest deck slot raise the win rate
      or lower it? **In the batch because it is a sim run and because its OUTPUT is card buffs**,
      which are per-class power changes. Needs a new audit; there is no existing one for this.
      Until it runs, *"53 cards exist and all 53 work"* is the honest claim.
- [ ] **Sage 1.3%, Barbarian 1.2%, Ranger 1.9% death per encounter** against 0.1-0.7% for the rest.
      Real but not broken, and all three clear the endgame bar. **Per-class levers only** - a global
      buff is cancelled by the next refit and cannot close a per-class gap. (Moved here from
      "Phase 2 - balance follow-through", 2026-09-18.)
- [→] **Feel check the rest change.** `REST_HEAL_MIN/MAX` replaced EIGHT sites, so meditate and <!-- audited: 2026-09-19 --> Re-marked: a FEEL CHECK for the owner, not work.
      companion regen scaled along with rest and mages got it twice. Owner: Meditate is the
      deliberate lever if mages come back too strong - check that BEFORE touching mage design.
      (Moved here, 2026-09-18.)
- [→] **Watch the five live characters at L3-L12.** `bash tools/check_player_progress.sh`. They sit <!-- audited: 2026-09-19 --> Re-marked: a WATCH NOTE, not work.
      in the range everything from 2026-09-07 targets and are better evidence than more simulation.
      Not a chain input - **read this BEFORE the batch runs**, because it can say the sim is wrong.
      (Moved here, 2026-09-18.)

### ⛑ "COMPLETE THE BACKLOG TODAY AND TOMORROW" — what that can and cannot mean

Owner 2026-09-17: *"I'd like to get it completed over the course of today and tomorrow."*

Counted mechanically: **51 open items.**

**⛑ AND MY FIRST ATTEMPT AT SIZING THEM WAS WRONG, so this is the corrected read.** I ranked the
items by how many lines of detail each carried and called the 19 shortest "a day's work". That
measures how much has been WRITTEN about an item, not how much work it is - and the shortest
entries on this list are `Sanctuary redesign.`, `Player phantoms.`, `Living world / rework the
posts.`, `Minigame variety.` and `Crafting review`. One line each, because nobody has written them
up yet. They are among the largest things on the list.

**Genuinely small, having read them:** the four gold-ring / starter-mark verification items, and
extending UI-scale registration. Five or six, not nineteen.

**Genuinely large but recorded in one line each** — these are the trap: Sanctuary redesign, player
phantoms, living world / rework the posts, minigame variety, crafting review (*"not in a good spot
at all"*), real sinks for excess eggs and companions, the Prize Shuffle redesign's remaining two
thirds, death replay, and the launcher revamp. Any one of them is a session or several.

**Cannot be done by me at all — needs an artist:**
* **Action poses for the 40 sprites that lack them.** The item says so in its own words: *"this
  is ART, not game code."* Same for the remaining buff icons, where the standing rule is not to
  press a spare debuff row into service.

**Cannot be done in two days — each is its own session or more:**
* **Sprite the overworld, Phase 2** — 51 lines of scope, and the backlog already calls it *"NOW
  THE BIG ONE"*. Includes NPC post interiors and the zoom-inside-a-post ask.
* **Party play, half two** — independent movement plus join-in-progress combat. 65 lines.
* **The full UI / navigation audit** — every menu path in the game, then retiring the 119 chat
  commands. It is the prerequisite for controller support, which is why it is not filler.
* ~~**The 53-dungeon card content**~~ — **DONE 2026-09-17, all 53.** Was: 4 of 59 authored. The
  quality bar is the four that exist.

**Blocked on an owner decision, not on effort** (each has its open questions written down):
post-to-post road travel;
judging the dungeon with a full party; the assassinate/Silver Tongue follow-ups.

**So the honest plan for the two days:** clear the five or six genuinely small items, take the
mediums that hold up, and put the blocked ones to the owner in one batch. What will NOT happen is
the list reaching zero - and a list that reaches zero by having its hard items quietly redefined
is worse than an honest one that does not.

**And the lesson from getting the sizing wrong:** a terse backlog entry is not a small job, it is
an unwritten one. Sizing this list needs the items read, not counted.


### ⛑ THE LEGACY POST SYSTEM — AUDITED 2026-09-17, needs an owner decision

Owner: *"It sounds like we need to remove or structurally resolve the legacy post stuff just like
the dungeon list problems."* Right instinct. The audit found it is **three things, not one**, and
one of them is a FEATURE THAT IS SILENTLY OFF.

**1. `trading_post_db` is LIVE and legitimate — do not remove it.** It owns what a post *sells*:
`resolve_post_category`, `category_has_npc_stock`, `get_npc_daily_stock`,
`get_specialty_discount`, `get_specialty_summary`. Twelve live call sites. `chunk_manager` owns
where posts *are*; this owns what they do. That split is fine.

**2. `TRADING_POST_COORDS` (58 hardcoded coordinates) points at empty ground.** Measured against
the real world (`npc_posts.json`, 120 procedural posts): **11 of the 12 sampled have no post
within 3 tiles.** Only "crossroads" (0,0) coincides with a real post. Read by
`_regenerate_progression_quest`, travel-quest distance, and exploration destination display.

```
haven          (   0,  10)  nearest real post 10 tiles away
south_gate     (   0, -25)  25 tiles
east_market    (  25,  10)  27 tiles
northwatch     (   0,  75)  75 tiles
```

**3. ⛑ THE PROGRESSION QUEST IS DEAD CODE, and has been since posts became procedural.**
*"Travel to the next trading post"* — the quest that guides a new player outward — can never be
offered. The chain, end to end:
* `handle_trading_post_quests` calls `_generate_progression_quest(tp.id, ...)`, where `tp.id` is
  a REAL post id
* real posts carry **no `id`** in `npc_posts.json`, so `_normalize_npc_post` synthesises
  `"npc_" + name` → `"npc_crossroads"`
* `get_next_progression_post("npc_crossroads", ...)` opens with
  `if not TRADING_POSTS.has(current_post_id): return {}` — and `TRADING_POSTS` is keyed by
  **legacy** ids like `"haven"`
* so it returns `{}` every time, and no progression quest is ever generated

**Worth being precise: this is DEAD, not BROKEN.** I was heading for the more alarming conclusion
(*"players are given quests they cannot finish"*) and it is not that — the quest is never offered
at all. Had it been offered it would have been uncompletable, because
`check_exploration_progress` matches the post id it is standing on (`npc_crossroads`) against the
destination id (`haven`), which can never be equal.

**THE DECISION (owner's, per CLAUDE.md's "archive with discussion"):**
* **(a) RESTORE it** — point progression at real posts. The data is all there: `npc_posts.json`
  has 120 posts with coordinates and names, so "the next post further out, in your level band" is
  a live query rather than a table. This gives new players a guided path outward again.
* **(b) REMOVE it** — delete the progression quest, `TRADING_POST_COORDS`, `TRADING_POSTS` and
  `get_next_progression_post`. The Warden onboarding chain now does the guiding job, which may be
  why nobody noticed this was off.

**Either way, the structural half is the same** and is the `base_tier` move again: **one owner for
"where is a post and what is it called"**, which is `chunk_manager`. The two legacy tables must
stop being readable for placement questions, so that asking them fails loudly instead of
returning a plausible wrong coordinate.

### ⛑ STILL OPEN after 2026-09-17 — the Atlas pin, live

The merged panel is built and the renderer is proven (`tools/probe/atlas_pins_and_rumours.gd`,
17 checks). **What is NOT proven is the pin on live data**, and chasing it found a real bug and
two facts about the world worth keeping.

**✅ FIXED: pins read a STUB, not a quest.** The pin was built from the entry in
`character.active_quests`, which carries `quest_id`, `progress`, `target` and a little
`extra_data` - and **not** the quest's name, nor the post to hand it in at. Worse,
`extra_data["dungeon_type"]` is only written for `DUNGEON_CLEAR`, so reading the stub would have
pinned **one of the four** dungeon quest types and silently ignored rescue, gather and boss-hunt.
Pins now hydrate the same way the quest LOG does: prefer stored fields, fall back to
regenerating the full definition from the quest id.

**⛑ And the lesson, which is the reason to write this down.** The probe PASSED on this code. It
passed because I handed the renderer ideal data - a pin with a name and a post - so it proved the
renderer draws what it is given and nothing about what the game gives it. A test that supplies
its own inputs cannot find a missing input.

**✅ ADDED `gm_goto_post`** — the sibling of `gm_goto_dungeon`. Everything that happens AT a post
(the quest board, the Cartographer, the arrival that records dungeon RUMOURS) was unreachable to
the harness because posts are procedurally placed and the only way there was to walk.

**⛑ NPC POSTS AND LEGACY TRADING POSTS ARE DIFFERENT THINGS, and that is what blocked the
capture.** `gm_goto_post` lands on the nearest **NPC** post (`chunk_manager.get_nearest_npc_post`),
but the quest board reads a server-side `at_trading_post` map that only
`trigger_trading_post_encounter` fills - and that function asks
`world_system.get_trading_post_at`, which finds **legacy** posts. So standing on an NPC post
leaves `at_trading_post=false` and the board never opens. The quest-board handler already knows
this (it has an `elif at_player_station.has(peer_id)` branch), which suggests NPC posts reach
their board another way. **Next step: find that route and give `gm_goto_post` the same one**, then
the live pin frame is one run away. Teleporting to `TRADING_POST_COORDS["crossroads"]` at (0,0) is
NOT the answer - it is a legacy table and that coordinate is empty ground.

### ▶ START HERE (2026-09-17 morning) — THE DUNGEON ARC, AUDITED

The owner chose **the Atlas as hub + quest board** to begin the arc, with *"ensure you're
tracking the cartography stuff as well (or just that it exists)"*. The audit is done; the design
is not started. **Read this block before touching the Atlas.**

**What the audit found, by following call paths rather than reading items:**

| arc item | reality |
|---|---|
| Dungeon-centred questing | ✅ **already built** (P2, 2026-08-26) — ticked below, no work needed |
| Atlas as hub + quest board | **not started** — this is the chosen piece |
| 53-dungeon card content | **DONE 2026-09-17 — 53 of 53**, cast-tested through the real processor |
| Themed floor equipment | **DONE 2026-09-17** — the affix pools' monster comments became a field; 53/53 types themed |

**✅ CARTOGRAPHY EXISTS AND IS COMPLETE** — the owner asked, and the answer is yes:
* ranks **1-8**, XP from discovery (**+20**) and clears (**+40**), `Character.add_cartography_xp`
* rank **3** → Cartographers give direction + distance; rank **5** → precise coordinates;
  rank **8** (`CARTOGRAPHY_SENSE_RANK`) → Locate **anywhere**, no post and no Valor
* already displayed at the top of the Atlas (rank, precision, XP to next), and rank-ups announce
  the capability they just unlocked
* **the hub already has a front door:** a Cartographer NPC (`K`) at a post calls
  `_handle_cartographer_station`, which opens the Atlas. Any hub design should use that rather
  than invent a second entry point.

**What the Atlas is today** (captured, `shots.py atlas`): a CODEX plus a locator. Per discovered
dungeon it prints a title row (name, grade, level band, clears) with a `[‹ Locate ›]` link, then
Monsters, then Boss + Companion egg — three lines each — and one summary line for the rest
(*"...and 35 more dungeon(s) still undiscovered"*). 12 lines with three dungeons known.

**What it is NOT, and what "hub" has to mean:**
* **no quests anywhere on it.** Questing is already dungeon-centred, so every daily quest points
  at a dungeon — and the screen that lists dungeons does not say which ones are wanted. Today a
  player reads the Atlas, then walks to a post to find out what it asks for. That gap is the item.
* no verdict against the player. The dungeon ENTRANCE screen now colour-codes monster level
  against your own; the Atlas does not, though it is where you choose where to go.
* no sense of progress beyond a clear count.

**✅ ANSWERED by the owner 2026-09-17 — build to these:**
1. The Atlas **SHOWS** quests, it does not accept them. Every accept stays at a post, so the post
   keeps being a reason to travel.
2. A quest **PINS its dungeon** in the list.
3. Rumours **display**, and can be quested toward — reading (a): the rumour row is informational
   and names the post offering it. No accept, no reward path, outside a post.
4. **One PANEL, two TABS — not one list.** Owner: *"Is there enough overlap to combine the two?
   I guess we will just need to ensure the difference between each is clear."* The overlap is the
   SUBJECT (dungeons), not the QUESTION: the Atlas answers *where do I go and what is in there*,
   the quest board answers *what am I asked to do and what have I got on*. One list would make a
   row sometimes-a-place and sometimes-a-task. So: shared shell and one set of doors, two tabs,
   and the difference carried by the VERB each row offers - Dungeons rows offer **Locate**, Quest
   rows offer **Accept / Turn In / Abandon**. The PIN is the bridge between them.
5. It lands in the existing `quest_board_panel` (a real card UI) rather than in the text Atlas,
   and the text Atlas + the orphaned text dungeon list both retire. Entry points converge:
   **Quests** button and `/quests` → Quests tab; **Atlas** button, the Cartographer NPC and
   `/dungeons` → Dungeons tab. No button is left pointing at a retired screen.

**⛑ That harness observation was NOT a bug — corrected 2026-09-17.** I filed `dungeon_exit`
not leaving the dungeon as a possible fault. It is the DESIGN: `handle_dungeon_exit` is
documented *"no free exit, must use escape scroll"* and the floor says so on screen
(*"You can't leave from here"*). The refusal was correct every time and the harness was asking
for something the game deliberately does not offer. `gm_finish_dungeon` is no help either — it
places the final chest but DEFERS the teleport until the player walks onto it. Neither is needed
now: the Atlas is a full-screen modal, so what is behind it does not matter. Surfacing only
mattered while the Atlas was text in `game_output`, where the dungeon owned the canvas.


### ✅ v0.9.798 IS LIVE (2026-09-16 evening) — client AND server, verified

Release gate PASS (958 dungeon-art lookups resolved, every performance guard intact), all seven
assets published, and the server swapped **in one restart**, verified by hashing the running
process (`81bf7a2031c2276d`) rather than the file on disk.

**It carries a live balance change, which is why it went out rather than waiting.** Dungeon
completion XP was computed from the dungeon's TYPE instead of its grade, so clearing an A-grade
Goblin Caves paid 300 XP where it should have paid 2,400. Chest contents were graded the same
wrong way. Nobody had reported either - both were found by the `base_tier` rename, which is the
argument for that rename in one line.

Shipped: the dungeon entrance screen as a skimmable table; modifiers stating their trade in
numbers; six surfaces that advertised a dungeon's TYPE grade instead of the instance's; the
numeric `T#` label gone from every dungeon surface; and the two reward formulas above.

### ✓ v0.9.795 (superseded, kept for the deploy notes)

Seven assets under `v0.9.795`, release gate PASS (including the new `state_icons` line), and the
server swapped **in one restart** and verified by hashing `/proc/$PID/exe` against the local build
(`3f62bbd5a238f9fe`). `tools/deploy_server_warned.sh`'s ordering held — stage the `.new` before
writing the countdown, `mv` the moment the PID changes — so players took ONE disconnect, not the
two that v0.9.793 cost.

**The server side mattered this time.** 131 lines of `server.gd`: `allies` on `dungeon_state`
(party members drawn underground), the `party_update` flush on batched character updates (gauges
that move), follower placement ordered before notification, `gm_apply_state`, and the dev-loopback
rate-limit exemption. A client-only release would have shipped a changelog making claims the server
could not honour.

**No re-calibration was needed and that was checked, not assumed:** nothing in the arc touched
player power, so the `speciescal`/`refcal`/`rolecal` chain does not apply.

### Shipped in v0.9.795


### ✅ 2026-09-16 — THE STRUCTURAL FIX: a dungeon TYPE no longer HAS a grade

Owner, after the fourth leak of the same bug: *"do the structural fix then so this doesn't happen
again."*

Patching call sites was losing. The grade leaked from the type into SIX player-facing places and
TWO reward formulas, each found separately, months apart, by a player noticing. The cause is that
`DUNGEON_TYPES[x].tier` was **reachable and looked right** at every call site.

**So the field is renamed.** `base_tier` is the type's DESIGN WEIGHT - an input to creation. `tier`
exists only on a dictionary an instance has resolved (`_dungeon_data_for`). A raw `get_dungeon()`
result has no `tier` at all, so the wrong read fails loudly instead of returning a wrong number.
53 type definitions, ~40 read sites, every one classified by walking back to where its variable
was assigned rather than by eye.

**And the rename found two silent BALANCE bugs nobody had reported:**

- `calculate_completion_rewards` computed `base_xp = tier * 500` off the TYPE. Clearing an
  **A-grade Goblin Caves paid 300 XP where it should have paid 2400** - the rarest, hardest
  version of a place paid the least, because the number came from the template.
- `roll_treasure` graded every chest in the world by the type, so the same dungeon regraded by
  the land kept its template's egg and material rarity.

Both now take the cleared grade. Measured: H 300 -> A 2400.

**Two detectors, both proven to fire by re-injecting the fault** (`tools/probe/dungeon_base_tier_invariant.gd`):
- the SHAPE: no type defines `tier`, `get_dungeon` does not add one back, and the reward formulas
  actually move with the grade they are handed
- the last quiet spelling: `dd.get("tier", 1)` still returns a default rather than failing, so a
  provenance walk - for each read of `x.tier`, find where `x` was assigned and judge THAT - fails
  on any display or reward site reading a type. Proximity was NOT used; it was tried for the
  sibling `T#` check the same day and was a silent no-op.

End to end after the rename, on a real `D` tile: overworld `G3`, warning `G3`, inside `G3`.

**⛑ Filed, not assumed:** `_create_world_dungeon_near` grades by the type's design weight while
`_create_world_dungeon` grades by `_grade_of_land` - so a dungeon spawned NEAR something does not
follow the land the way an ordinary one does. Surfaced by the rename. Making it consistent changes
world generation, which is the owner's call.

**⛑ Also filed:** `QuestDatabase.get_threat_relief_rewards` deliberately stays on the design
weight. It is called twice for one quest - when offered, and again from `quest_from_id` when a
saved one is rehydrated - and that second call has only the type, because the quest id encodes
post+type. Grading by the instance would promise one reward and pay another. Fixing it properly
means storing the grade in the quest record.

**⛑ And a stale probe found on the way:** `dungeon_grade_truth.gd` had been matching on a closing
paren that moved when `_inherit_starter` was added on 2026-09-14, so it had been failing silently
since. A stale probe looks exactly like a broken feature.

### ✅ 2026-09-16 — THE ADVERTISED GRADE IS THE ONE YOU WALK INTO

Owner: *"As long as the entrance screen matches what the actual instance the player will enter is
we are good. We don't need the overworld advertising F something and end up in a C dungeon."*

**This had already happened once** and been fixed in ONE place. A dungeon's grade belongs to the
INSTANCE, not the type (owner, 2026-09-11: *"an A5 Goblin Dungeon, or a S2 Kelpie one"*), so
`DUNGEON_TYPES[x].tier` describes nothing a player can walk into. The earlier report - *"a player
went into a pheonix dungeon that showed as F4 or near that on the overworld and instead it put
them in a C5"* - was fixed for the dungeon's name INSIDE the dungeon. Four more surfaces were
still reading the type:


Already correct, and left alone: the overworld map hover and the entrance panel, both of which
resolve through `_dungeon_data_for(instance)`.

**Measured end to end, because reading the code cannot answer it** - both numbers are real and
both look right at their own call site. `gm_goto_dungeon` stands the harness on a real `D` (every
other GM route passes a bare `dungeon_type` with no instance, which resolves off the TYPE and so
hides the bug), and the `dungeongrade` shots scene reads the grade off all three screens a player
sees:

```
GRADE overworld entrance : 3-1  (Orc Stronghold [F1])
GRADE entry warning      : 3-1
GRADE inside the dungeon : Orc Stronghold [F1]
PASS overworld and warning agree
```

Not a vacuous pass: the first run drew a Wyvern's Roost, whose TYPE is tier 3 (F) standing as a
tier 2 (G) instance. **Proven to fire** by reverting the warning fix - it caught a Goblin Caves
advertised G2 on the overworld and H2 on the warning.

**⛑ The class is not retired, only its instances.** `get_dungeon(type).tier` is still reachable
and still looks right at every call site - 40 reads across the codebase, most of them legitimate
creation-time inputs that genuinely want the type's base. The structural fix is to rename the raw
field (e.g. `base_tier`) so a display surface CANNOT read a type's grade by accident. That is a
~40-site change spanning creation and display and wants its own session - **filed, not assumed.**

### ✅ 2026-09-16 — NO DUNGEON SHOWS A NUMERIC TIER ANY MORE

Owner: *"T# dungeons shouldn't exist anymore as all dungeons are now on the letter number format."*

The letter ladder (H G F E D C B A S) replaced the numeric tier on 2026-09-11 and **seven surfaces
never got the message** - the exact shape of CLAUDE.md's "a rename touches SEVEN surfaces" rule.
Swept, not spot-fixed:


`PowerRank.rich_grade(tier)` is the new formatter for a surface that names a KIND of dungeon rather
than one you can walk into. A dungeon TYPE has a grade but **no rank** - the rank is rolled per
INSTANCE, by distance from origin (`get_sub_tier_for_distance`) - so those surfaces show the letter
with a hover that says so, and every instance-level surface shows the full `F7`.

**⛑ The detector was a silent no-op on its first run, and only re-injecting the fault found it.**
It flagged a line carrying `T%d` *and* the word "dungeon"; on the GM line the dungeon NAME is on the
next source line, so the token sat there and the probe said PASS. Proximity was the wrong unit. The
token is BANNED now and the legitimate non-dungeon uses (gathering nodes, tools, trading posts, the
region readout, monster tier, one admin diagnostic) are NAMED individually - unsafe unless listed.
Re-proven by re-injecting `(T%d)` into the GM line: FAIL, then PASS on revert.
Probe: `tools/probe/dungeon_grade_format.gd` (49 checks).

### ✅ 2026-09-16 — THE DUNGEON ENTRANCE SCREEN, SKIMMABLE

Owner: *"The current Dungeon warning screens are a wall of text though. They need to be able to be
skimmed and know what you're getting into."*

It ran past twenty lines. A seven-line prose paragraph built on the SERVER, then a five-line
recovery lecture, then a full sentence for every theme tile - and the two numbers the decision
actually turns on, what level the monsters are and what level you are, buried in the middle of it.

**Reformatting it on the client could never have fixed it.** The sentences are built server-side
and shipped as one `message` string, so the client could only re-wrap them. The payload carries
FIELDS now (`entry_level`, `deepest_level`, `floors`, `modifiers`, `tier`, `sub_tier`) and the
screen is a table: one fact per row, fixed label column, ordered by what the decision turns on.
`message` is still sent as a one-line fallback, because a client from before this release has
nothing else to show and an empty warning is worse than a wordy one.

Measured, not reasoned about — `python tools/test_setup/shots.py dungeonwarn`:

```
═══ FORGOTTEN CRYPT ═══  H7
  Monsters   Lv 4453-5618  — far above you   (you are 20)
  Unusual    Ironbound   35% more armour              +15% XP
  Floors     5  - the boss is on the last one
  Ground     % Bone scatter  (hover)
  Food       559 - resting inside spends it; nothing else heals you
  Exit       Escape Scroll or kill the boss - there is no free way out
  Hard mode  available  +50% monster stats   +75% XP, bonus loot
```


### ✅ 2026-09-16 — INSTANCED CARDS: the deck screen now manages CARDS, not counts

Owner: *"All classes should only start with 1 copy of each of their cards... get rid of the + on
the deck screen unless the player has two exact copies of a card (same rank, same number of uses,
same upgrades, etc.). If not all cards should appear individually... they should not both track
usage for the skill itself being used, it should instead track the number of times that unique card
has been used."*

**Two of the three were already true, and that was MEASURED before changing anything**
(`tools/probe/deck_starts_with_one.gd`):


**The deck screen was the real gap, and it is fixed:**




### ⛑ NOT VERIFIED IN v0.9.795 — look at these first


### Open, in order




- [→] **Judge the dungeon with a full party — AWAITING THE OWNER, not work.** Nothing is blocked
      on code here; it is a look-and-say. Marked distinctly so it stops reading as a task nobody
      has started. The owner has frames at the right tile size now
      (`shot_38675`, `shot_50715`); the call is theirs.


### ⚑ 2026-09-16 afternoon — the party/dungeon round (commit `fc6542d2`, UNRELEASED)

Worked from the owner's frames of a five-person party run. All of it is on master, none released.

**DONE, each verified in a capture:**
- Shortcut buttons have ONE home, above the action bar, on every screen. They rode the travel row
  (overworld-only), so underground they fell back to the top of the side column.
- Party members are DRAWN on the dungeon floor. Nothing on that wire had ever described another
  player: the overworld reads world x/y and underground everyone's coordinates are instance-local,
  so `get_nearby_players` cannot see them. `dungeon_state` carries an `allies` list now.
- The party strip and the dungeon key sit at the BOTTOM of the dungeon canvas as anchored Controls,
  not as text printed after the floor.
- The dungeon uses its canvas again: 64px tiles, matching `shot_26639`, which the owner named as the
  reference. Measured `avail=662 h_room=578 tile=32` against the 576 a 64px tile needs — two causes,
  a stale 56px headroom for the retired step counter and `game_output` being shrunk by the party
  strip's band. The tile now comes from the WIDTH and the row count from the height that is left.
- The canvas frame contains everything. Measured: canvas 792, bordered label 722, and three widgets
  anchored at 756/762/792. Shrinking the bordered box to make room *inside* it can only look wrong.
- Party gauges MOVE: `party_update` used to be sent only when the membership changed, so the bars
  were a snapshot from the moment you grouped up. It flushes with the batched character updates.
- "Party none" when solo; companion box hidden when there is no companion (two functions owned one
  `visible` and the later one won); one `_hp_bar_color` for every health bar; companion HP gauge.
- The party capture scenes wait for FIVE (`PARTY_MAX_SIZE`), not three.

**THE BARS TOOK FOUR ATTEMPTS. Read this before touching them again.**
Pipes (`|`) read as a dashed line. `[bgcolor]` runs are LINE-height slabs, and on the dungeon canvas
— whose font is the tile font — they were enormous. Block glyphs (`█`/`░`) were rejected too. The
shared cause is that all three were CHARACTERS, and the owner's reference (*"closer to Lufia 2 or
dothack"*) is a thin slab with a dark outline, a recessed track and a rounded bright fill, which no
glyph can be. They are `ProgressBar`s with two `StyleBoxFlat`es now. The companion's gauges are
Controls pinned into bands its stylebox holds open — blank lines do NOT work, because `fit_content`
will not grow a label for an empty trailing paragraph, so a bottom-anchored bar lands on real text.

**ALSO DONE this round (commits `bafc9ba8`, `724108b0`):**

**⛑ AND THE LESSON THAT COST THE MOST TIME TODAY — a `.gdignore` makes `exists()` lie.**
`client/sprites/battlers/tf_svbattle/` (and eight other asset-pack folders) carry a `.gdignore`, so
nothing under them is imported, nothing reaches the `.pck`, and `load()` returns null — while
`ResourceLoader.exists()` returns **true**, because the `.import` sidecar is there. An `[img]` tag
whose texture fails to load draws **nothing at all**: no gap, no placeholder. So the Effects box
looked byte-identical to before the icons were added, and three `[img]` tag forms were A/B/C-ed in
two labels before anyone asked whether `.godot/imported/` held a `.ctex` for it. **Art you want to
use must be copied OUT of those folders**, and the check is calling `load()`, never `exists()`.
`--buildverify` asserts the state sheet loads for exactly this reason.

**STILL OPEN from this round:**


### ⛑ v0.9.794 - HOTFIX, and the two things it taught (2026-09-16 morning)

**I shipped the Deck screen empty.** The guard that stops the old keyboard ability screen printing
under the panel was placed ABOVE `_populate_ability_panel()` - the call that fills the panel. Owner,
on the live build: *"Looks like you broke the Deck screen completely last night. Can't see any cards
on it."* It is the SAME mistake I had fixed in `display_market_main` an hour earlier in the same
session: populate first, guard second. Writing the fix once did not stop me repeating the bug.

**And the sweep found six more of it.** Auditing every guard I had added showed six market
sub-screens (list select, materials, eggs, network browse, network inspect, buy confirm) where the
panel renders nothing of the kind - so the guard would have opened them blank. Those guards are
gone; the three the panel really does render (main, browse, inspect) populate first.

**The stance flash was a RE-SHOW, not a late hide** - which is why two fixes aimed at the hiding
path changed nothing. Measured with timestamps: the row was correctly hidden 15ms after the market
opened, then `update_action_bar` put it back (its rule was only "not in a dungeon"), and it hid
again 230ms later. Both unconditional `_stance_bar.visible = not dungeon_mode` sites now also ask
`_margin_widgets_shown()`. Re-measured: hidden the whole time the menu is open, back on exit.

**Both lessons are the same one, and it is already in this file:** when a fix does not take, the
question is not "is my logic right" but "what else writes to this". The instrument that answered it
in one run each time was a probe that pressed the real button and printed the real state - and it
also caught its own wrong action id, which reading the code had not.

### ⛑ v0.9.793 IS LIVE (2026-09-16 02:10) - UI ARC SHIPPED UNFINISHED, ON THE OWNER'S CALL

Released and deployed: seven assets under `v0.9.793` (Windows + Linux client and launcher, the pck
and runtime split, the generated manifest), release gate PASS on the Windows client, and the server
swapped and verified by hashing `/proc/$PID/exe` against the local build.

**The swap needed a second restart.** The countdown ran, systemd's `Restart=always` brought the
server back on the OLD binary before the `mv` landed, and the running hash proved it - so the
restart was done again and re-verified. Two disconnects for anyone who was online at 06:09 UTC.
The runbook's advice (swap DURING the window) is right but the window is smaller than it reads:
**stage the `.new` file BEFORE writing the sentinel, and do the `mv` the moment the sentinel is
consumed, not after polling for a PID change.**

Owner, going to bed: *"make sure to document and update everything properly. Go ahead and push a
release as well. We will work through the bugs in the morning."* So v0.9.793 is the UI reflow as it
stood at 02:00, **with two screens never looked at** - the dungeon and party combat - and the stance
timing still open. That was said plainly before shipping; it is not a surprise to find in the
morning, it is the deal that was made.

**START HERE IN THE MORNING: the four open items below, then walk the dungeon and a party fight.**

### ⛑ WHERE THE UI ARC STOPPED (2026-09-16 ~02:00, owner went to bed)

**Nothing is released. Master carries an unreleased UI reflow** built live with the owner over one
session, screen by screen: they drove a local client, said what was wrong, and each fix was checked
against what they saw rather than against what the code implied. Commits `1073a558`, `121019c9`,
`9220fd1b`, `c4553326`, `59de13fa` and the ones after them.

**The shape of it.** The overworld map owns the main canvas. Its margins - the ~300px either side
of a square map in a wide canvas - hold the HUD: Coords and the status panel and the chat box on
the left; the minimap, Area, Effects, Party and the companion on the right. The right column is the
LOG, full height, and the bottom strip is the action bar and the input row only. Text follows one
rule: **if it fits in the column it goes there, and if it does not it takes the canvas** - measured
as the page is built, never a list of screen names. Visual menu panels (Inventory, Companions,
Market...) keep the canvas as they always did.

**What the owner still has open, in their words:**
**FIXED at the last minute, by measurement:** the Pouch's Back button is bound to
`more_subview_back`, NOT `pouch_back` - so two rounds of fixes went to code that was never being
pressed. The `backtest` shots scene (added this session) opens each screen the way the shortcut row
does, presses whatever slot 0 actually holds, and prints whether the world came back. It named the
binding in one run, and it also caught its own first version pressing `jobs_close` when the action
is `job_close`. Every sub-view of the More menu goes through one exit now.


### ⛑ WHAT THIS SESSION COST, AND THE TWO LESSONS WORTH KEEPING

**Every wrong fix this session came from reasoning about the code instead of measuring the screen.**
Three in a row: the map "lines" were a `[url]` underline, not line spacing; the "Crossroads flash"
was the client's own per-step redraw, not the location handler; the darkness was a StyleBoxFlat
SHADOW - a filled rounded rect drawn under the box as well as around it, which is invisible behind
an opaque fill and a black wash behind a transparent one. Each was found in one run by looking at
pixels or by printing state, after two or more failed attempts at reading.

**A list of screen names is always the wrong instrument here.** It was wrong for which pages take
the canvas (`jobs, pouch, build, etc.` was the owner pointing at the gap), wrong for which text is
a station page, and wrong for which menus are panels. Every one of those is now a property the code
can ASK: is it taller than the column, did it clear the canvas, is there a visible `*Panel` child.

## ▶ PREVIOUS SESSION BLOCK (2026-09-15 evening, after v0.9.791)

### ⚑ WHERE THINGS STAND

**LIVE: v0.9.792 (2026-09-15 night). Nothing is held on master.** The equipment/item audit and
everything it found is out, gear now reaches your cards, the monster curve was re-calibrated for
it (speciescal -> refcal -> rolecal, one pass each, every level inside +/-10pp and the death column
at or below 0.9%), and a kill in a party finally pays what it is worth. Full write-up in the
v0.9.792 section below; the onboarding arc that preceded it is in the v0.9.790/791 sections.

The server binary was swapped DURING the countdown, so players took one warned disconnect; the
running process was verified by hashing /proc/$PID/exe against the local build.

**Seen only in probes, not yet in a running client:** teammate damage numbers in co-op, the party
status strip, the Warden in the dungeon and his walk home, and the three new lessons. The owner's
last local run covered cards, the walk and the lessons; watch the rest in the next co-op fight.

### ▶ RECOMMENDED ORDER (2026-09-15)

Ordered by what players hit first and what the next item depends on. Big-arc work comes after the
live defects because the arc adds more of exactly the surfaces those defects live in.

1. **⛔ INSTANCED CARDS ARE NOT WORKING — live since 2026-09-14** (full report further down, under
   the owner decisions block). **Complaints 2 and 3 FIXED on master 2026-09-15, not released**
   (`d34ea3f0`, probe `card_copies_visible.gd`, proven red on the old code):
   - measured cause of the back-to-back screens: a level-up in a PARTY fight (every Warden fight)
     queued its choice and nothing announced it - the flush was missing from the card-command
     path - so choices piled up and arrived together later. Every resolved party round flushes now.
   - copies were indistinguishable: the upgrade screen now says "copy N", the deck draws one tile
     per copy with its own progress and upgrades, and each copy can be thinned/restored by name.
   - checked and RULED OUT on the way: picks failing on dungeon/companion cards (they land fine),
     and double-queueing on login reconcile (idempotent). Live saves (18 characters) hold no
     dungeon card and no second copy of anything, so complaint 1 is still unexplained.
   **✅ RESOLVED 2026-09-15 (unreleased) - complaint 1, the dungeon card award being "invisible".**
   It was never invisible: `_roll_dungeon_card_reward` pays a card with probability
   `min(0.30, (0.05 + tier*0.02) * (1 + (rank-1)*0.1))` and the completion screen only ever spoke
   when one DROPPED. MEASURED over 4000 clears a cell (`tools/probe/dungeon_card_odds_spoken.gd`):
   the STARTER dungeon pays **7.2%** of the time (stated 7.0%), tier 5 rank 1 14.6%, tier 9 rank 9
   29.6%. So 93 runs in 100 the honest answer was silence - which reads exactly like a bug, and
   fits the live saves holding no dungeon card across 18 characters. Nobody was losing cards;
   almost nobody was being given one. The screen now speaks either way, naming the odds and the
   card this dungeon is the only source of, with the odds carried back from the roll so the two
   cannot drift. Party members get the same answer on their own copy.
   Follow-up worth a decision: only 4 dungeon types have an exclusive card, so most dungeons fall
   back to a generic copy-drop and have no named thing to chase.
2. **✅ DEATH CURSE resized — DONE on master 2026-09-15, not released.** Owner: *"It often puts a
   player to 1 hp meaning it could be death in a flock or if they can't heal."* Measured: it was 10%
   of the MONSTER's max HP - from ~40% of a real player's bar at the low end to 100-500% for most
   carriers, most levels and every elite, so it usually left the player at 1 HP. Every carrier CAN
   flock: an empowered Broodcalling monster forces a 100% flock and the flock is the same species.
   Owner chose **20% of the player's max HP** (Wisdom resists up to half, still never lethal, Undead
   still immune). Trait chip and help text updated. Probe `death_curse_sized.gd` (real kill path).
   - [x] **Party fights never applied death curse at all** — **FIXED 2026-09-17. Owner: everyone
         in the fight.** `_process_victory_with_abilities` returns early on `suppress_victory` (a
         member's killing blow must not run the solo victory) and the curse lived below that
         return, so an ability the monster's own trait chip advertises did nothing whatever in
         co-op — the format the owner most wants players in.
         Everyone is also what it MEANS, and it scales honestly: the curse has been 20% of the
         **player's own** max HP since 2026-09-15, so each member pays the same fraction of their
         own bar and a party is not punished four times over. Measured: Fighter 295 of 1989,
         Wizard 208 of 1442 — different amounts because their Wisdom differs, which is proof the
         shared function does per-character maths rather than one figure for all.
         **Structural, twice over.** (1) The curse is now `apply_death_curse()`, one function that
         solo and party both call — copying 25 lines into the party layer would have given the
         WIS resist two places to drift, which is what happened the last time this shape appeared
         here. (2) `resolve_party_round` had **two** victory exits building their results inline,
         which is how something added on victory fires on one path only; both go through one
         `_party_victory()` now, and the probe fails if either builds its own again.
         ⛑ **The first extraction was a silent no-op.** The lifted block kept its original
         indentation under a new guard clause, so the whole curse sat INSIDE
         `if not (ABILITY_DEATH_CURSE in ...): return`, after the return. It parsed clean and did
         nothing. Caught by reading the function back, not by the compiler. Probe section proven
         to fire by injecting the fault (3 checks go red).
3. **✅ A REAL card-face instrument — DONE on master 2026-09-15, not released.**
   `tools/probe/card_face_truth.gd`: every class, every deck card that quotes damage, levels 20 and
   200, engine 0 and 4, server quote vs the mean of real casts (zero defence, level-matched, crits /
   Chaos Magic / double casts and kill-outright finishers excluded as the quote excludes them).
   Its first version was itself wrong twice (quote and cast from different randomly-geared
   characters; lethal finishers averaged as damage). Measured with it fixed: 78 cells, ONE genuine
   fault - **Barbarian Rampage left out the Rage ramp** (under-quoted ~1.5x at 4 Rage), fixed.
   Everything else within 15%. `card_vs_server.gd` deleted - it measured the retired client fallback.
   Not covered yet: party casts (they read the same builder), gear upgrades like Keen, and the cards
   that quote a non-damage effect (shields, heals, debuffs).
4. **FULL EQUIPMENT / ITEM AUDIT (owner 2026-09-15).** *"We need to do a FULL equipment/item audit
   covering all equipment possible in the game (including hunt equipment and special drops from
   monsters and dungeons as well as their chests and crafting). We need to see what still works and
   what is broken or needs revised, for example things that give +1 to warrior abilities (does that
   work and what does it do, etc.)"* Same class as item 3 - an item promising what the game does
   not do - and it goes BEFORE the dungeon arc, because dungeon rarity pays out in exactly this loot.
   **In-combat item use is IN SCOPE (owner 2026-09-15):** *"ensure it also tries to use items in
   combat. Some aren't meant for in combat use and may cause problems or unexpected things to
   happen."* Every usable item type (potion effects table, scrolls, tomes, home stones, charms,
   lanterns, eggs, crafted consumables...) is USED mid-fight through the real handlers - solo
   `handle_combat_use_item` and the party item path - and classified: works as intended / refused
   cleanly / refused but consumed / script error / unexpected side effect (leaves combat, teleports,
   opens a menu under the fight, grants twice, etc.). Owner asked to be ASKED about anything whose
   behaviour looks wrong or is unclear rather than having it decided silently.
   **Found while fixing the floor count, belongs here:** `handle_inventory_use` consumes an item
   BEFORE dispatching to its effect, so a refusal inside any effect branch still eats the item. The
   Floor Skip Charm is refunded now (`_refund_used_item`); every other refusal branch in that handler
   needs the same check (measured list below). Structural fix: validate before consuming, in one
   place, rather than a refund per branch.
   **MEASURED 2026-09-15** (`tools/audit/equipment_audit.gd`, `tools/probe/items_in_combat.gd`; every
   row executed, instrument defects found and fixed first: a no-weapon baseline, a shallow `to_dict`
   snapshot that hid every buff change, a companion modifier that was never parsed):
   - ✅ FIXED: **Enhancement Scroll on capped gear DUPLICATED the scroll** (the refusals re-inserted a
     scroll never removed). items_in_combat now FAILS on any duplication.
   - **Combat Use Item eats items it has no branch for.** `process_use_item` accepts anything in
     POTION_EFFECTS but only handles heal/resource/buff/taunt/revive, and the client's combat menu
     OFFERS nearly all of them: every stat tome, skill tome, bane potion, resurrect scroll, debuff
     scroll, Time Stop, Boss-Slayer Tonic, Reclaimer's Lantern, Floor Skip Charm, Mysterious Box, gems,
     pouches, cursed coin, travel stone and home stones are removed with only "Free action" printed.
     OWNER DECISION pending: which work mid-fight vs refuse.
   - **`inventory_use` has no combat gate:** mid-fight it heals outside the one-free-item rule, and a
     Floor Skip Charm moves you down a floor with the fight still running.
   - **Consumed by a refusal (out of combat):** Revive Potion with no/healthy companion, Taunt Charm,
     potion aimed at a knocked-out companion ("can only be revived by a healer" - revive potions exist),
     Travel Stone (eaten silently, no message).
   - **Crafted scribing output cannot be used at all** ("cannot be used directly. Try equipping it"):
     both Area Maps, all six Spell Tomes, Worldtree Tome, Bestiary Page, and the Weakness /
     Vulnerability / Slow / Doom / Monster Select / Target Farm scrolls - the empty-effect check runs
     before the scribing branches. The debuff branch also hardcodes "weakness".
   - **Crafted scrolls write buff names combat never reads:** Rage / Dragon Fury ("attack") and
     Forcefield / Sea Ward ("shield") do nothing. Tier-scroll names (strength, forcefield) are read.
   - **Apex Sigil drops as junk:** `_generate_item` builds it as an epic affixed non-consumable with no
     `item_type`, so `_use_apex_sigil` returns silently. 8% from apex kills.
   - **Skill tomes:** damage tomes for Bolt/Meteor/Power Strike/Cleave/Ambush/Exploit exact. Cost tomes
     over-apply (Efficient Strike 10% -> 28% cheaper, Efficient Vanish 15% -> 33%). Greater Forcefield
     and Devastating Berserk do nothing; Swift Analyze (Analyze already ~free) and Efficient Bolt
     (Bolt's cost is what you pour in) cannot matter. Owner: *"Lots of those items were designed before
     we had our current classes or their decks/abilities so they likely need expanded or new ones
     added as well"* - the tome set wants a pass against today's nine decks.
   - **Gear:** +1 Warrior dmg works (Power Strike +12%) but ANY wear (even 1%) truncates it to 0.
     Trickster rank affix misses Vanish, Perfect Heist, Gambit; Mage misses Frost Nova (hand lists).
     damage_mult, attack_bonus, crit_damage and proc lifesteal reach the basic attack only (Power
     Strike +0%); crit_chance barely (+3%). Proc runes (`proc_effects`): no effect.
     extra_turn_chance uncapped (150 = the monster never acts; one item at L900 rolls ~95%).
     A crafted item's own attack/defense/hp/speed is ignored, and `apply_rarity_bonuses` matches bare
     "helm"/"weapon" while crafting names items "<slot>_crafted", so crafted rarity bonuses never land.
     Source-read only: wish upgrades read `item_type` (items store `type`); Void/Abyssal/Primordial
     rune recipe fields have no reader.
   **OWNER DECISIONS 2026-09-15** on the measured results:
   - **Fight items:** *"It should refuse if it doesn't have a combat effect."* Refused, KEPT, and not
     offered by the combat menu. One predicate for "has a combat effect", read by the server's combat
     path and the client's menu filter.
   - **Gear vs cards:** damage_mult / attack_bonus / crit / proc stats **reach cards**, then the
     calibration chain (preflight -> speciescal -> refcal -> rolecal) runs once - player power moves.
   - **+N ability ranks:** *"We should probably do away with +1 as it isn't clear. There should
     instead be equipment that increases specific skills (ensuring it actually benefits the skill and
     doesn't give like + damage to a skill with no damage)."* Retire the archetype rank affixes;
     replace with per-card affixes whose stat is one the card actually uses (damage only on damaging
     cards, shield on shield cards, duration on buffs...). Existing items need a migration. Supersedes
     the wear-truncation and missing-card-list findings.
   - **extra_turn_chance:** cap at **30%** total across gear.
   **PROGRESS 2026-09-15 (all on master, probes `items_in_combat.gd` + `equipment_audit.gd`):**
   - ✅ one consumable resolver in drop_tables for every use path; refuse-and-keep without a combat
     effect; inventory_use mid-fight takes the fight's rules; refusals before the spend; crafted
     scribing / bane / heal-percent / debuff items usable; crafted buff names mapped to readers;
     readers added for xp_bonus (solo AND party), rare_drop, reclaimer_lantern; Area Maps mark tiles.
   - ✅ Apex Sigil is a real consumable (and works mid-fight); one use of a stacked Escape Scroll /
     Compass / Ability Tome / Sigil no longer deletes the stack.
   - ✅ proc runes proc; crafted armour and potions get rarity bonuses (legendary potion: 3 uses,
     1.75x - a designed table that was never live); Greater Forcefield and Devastating Berserk tomes
     work; gear extra-turn capped at 30%.
   - CORRECTED: the cost tomes were never over-applying - the audit compared different random
     characters and measured net-of-refund cost. Both exact. crit_chance DOES reach cards (+12%).
   - OPEN, need owner: crafted gear's recipe attack/defense/hp/speed (and Tempering) are never
     read - the aggregator gives crafted gear the same level/rarity base as a drop; Void / Abyssal /
     Primordial Runes cannot be crafted (no target_slot or effect - always "no equipment", refund);
     Efficient Bolt and Swift Analyze cannot matter (tome pass vs today's decks); Cursed Coin still
     drops from two tables and "crumbles to dust".
   - **OWNER 2026-09-15 on those:** crafted recipe stats and Tempering **add on top** of the level
     base (player power - into the calibration pass); Void / Abyssal / Primordial become **top-tier
     runes** (+attack weapon, +defense armour/shield, +HP helm/armour/shield); skill tomes **fold into
     the per-card bonus table** shared with the card-specific gear; Cursed Coin gets a **new effect**
     (I propose, owner picks).
   - ✅ DONE: crafted recipe stats + Tempering count on top of the base (and the client's item
     comparison now calls the server's per-item function instead of a drifted mirror); the three
     crystal runes are runes; Cursed Coin flips - heads, 3 fights of +1 rarity loot; tails, the next
     foe is an elite (owner picked). All executed in items_in_combat.gd / equipment_audit.gd.
   - ✅ DONE (player power - UNCALIBRATED): gear reaches cards. damage_mult in the card damage funnel
     (+50% -> Power Strike +50%), gear crit damage in the card crit multiplier, equipment lifesteal /
     Shocking / Execute fire on card hits (one shared function), and gear ATTACK at a reduced share -
     owner: *"cards getting a reduced amount so [attack] still has a place"*. ATTACK_CARD_SHARE 0.25 of
     gear attack over the level's expected stat (class-neutral; a Fighter's cards get ~half its basic
     gain at L60/L300). **⚠ master now carries a player-power rise with NO refit - do not release
     before preflight -> speciescal -> refcal -> rolecal** (after the per-card affixes land, once).
   - **CARD-SPECIFIC GEAR - owner decisions 2026-09-15:** magnitudes **15/30/45%** (duration +1/+2/+3
     rounds); old archetype rank items convert to **one random card** of that archetype; they drop
     where rank affixes drop today (epic+ chase pool); **one tome per eligible card+kind** replaces the
     14 fixed tomes (old tomes keep working, Efficient Bolt / Swift Analyze stop dropping).
     Eligibility is MEASURED (tools/probe/card_bonus_fit.gd, identical across every class holding a
     card): POWER+COST - ambush cleave blast distract exploit forcefield frost_nova gambit meteor
     perfect_heist power_strike sabotage shield_bash vanish war_cry; POWER+COST+DURATION - berserk
     fortify haste iron_skin rally shadowstep; POWER only - analyze devastate magic_bolt; COST only -
     banish paralyze pickpocket.
   - ✅ DONE (player power - UNCALIBRATED): card-specific gear built. shared/card_gear.gd is the one
     definition (measured KINDS table, 15/30/45 tiers, legacy conversion, text, tomes). Gear power /
     cost / duration add into the funnels tomes use; the twelve rank chase entries became card rolls in
     the same slots; every skill-tome drop became a card tome (38 entries, same weights); old rank items
     read as +15% power per rank, archetype items as one card picked from the item id (stable across a
     JSON round trip); gear cost reduction caps at 75%; tomes and gear now apply to every copy of a card
     (a second copy used to lose its tome bonus). Client item text, compact tokens and comparisons read
     card_gear. Measured in equipment_audit.gd; items_in_combat.gd uses a card tome; card_bonus_fit.gd
     FAILS if the table drifts from what cards measurably do (full run ~10 min, not yet run with the
     guard). ✅ `docs/design/equipment_reference.md` regenerated 2026-09-17 (`-- gearsources`); it was
     nearly current - one line moved, `scroll_time_stop` joining the mystery-box pool.
   - OPEN, small: card_face_truth fails ONE cell, Sage L20 Frost Nova at 4 engine (quote 250, real
     211, 0.85) - present before the gear change too (stash-tested), so an existing over-quote.
   - ✅ FIXED (player power): the "defense" buff was read TWICE per hit - as % damage reduction (the
     unit every card states, "+X% defense") and again as flat defense. Measured on a Wizard: a 50
     buff cut damage 52% (50 + ~5). The flat read is gone. Stone Skin wrote a share of total defense
     (~38 at L60) that read as 38%; it writes its tier percent now (Standard +15%, matching its text).
     NOTE for balance: a Fighter opens every fight AT the 85% mitigation cap (stance DR 60 + defense
     ~69%) - deliberate per the 2026-09-05/06 polytest notes, so not changed.
   - ✅ DONE 2026-09-15 (and it was WORSE than logged): a kill's XP had FOUR sums. The live co-op
     payout (`_end_party_combat_all`) had no sum at all - it paid `experience_reward` and called
     add_experience. Owner, live: *"I killed a Venomous Hobgoblin Lv 7 in a Hotzone area. I'm
     level 7 as well. I only got +195 XP"* - 195 was the monster's base, the number Size Them Up
     had quoted before the kill; solo that kill is worth 361. Missing in a party: the flat +10%,
     Danger Zone +30-70%, the level-gap curve, apex frontier/variant, Hunter's Mark, Path xp_pct,
     Insight, Easy Prey, the race/Sanctuary multipliers (it wrote `experience +=`), and the
     companion's 10% share. Perfect Heist was a third copy, patched twice for missing terms and
     still holding the coefficient solo left behind (0.7 against 2.0). `combat_manager.kill_xp` is
     the one sum; probe `tools/probe/xp_one_sum.gd` runs the real payout and was proven red
     (214 paid against 361 earned, five of five cases).
   - OPEN, investigate:
     crafting output is handled by two near-identical match blocks (server.gd ~26612 and ~27667).
   Fix order: item-use validation (the class, not per branch) -> crafted scribing / crafted buff names /
   Apex Sigil / proc runes / crafted stats -> skill tomes -> extra-turn cap -> per-card affixes (design
   the table first) -> gear stats reach cards -> calibration chain LAST, once.
   Method, per CLAUDE.md's equipment rule: walk ACQUISITION PATHS by calling each generator (drop
   tables, hunt, monster-ability drops like `warrior_hoarder`, dungeon floor loot and chests,
   crafting, merchants, uniques/sets), then PROBE each stat by equipping it and diffing what combat
   actually reads. `-- gearsources` and `docs/design/equipment_reference.md` are the starting point,
   not the answer - they already found stats with no reader once. Deliverable: a table of every stat
   and item family with works / broken / misleading, then fixes in order of how many players carry it.
4a. **SHIPPED in v0.9.792.** (Kept for the record of what the live two-player session found.) a second
   new player's Warden and map ring pointed at the FIRST player's personal copy of the starter
   dungeon (random spot, no entrance, can be in a hotzone). Fixed on master 69d0f37e, probe
   `starter_dungeon_two_players.gd` (red on the old code). Workaround until then: walk to the real
   entrance's coordinates.
   Also for that release (same live session): a Warden (party) fight underground wrote "YOUR TURN"
   and card lines into the dungeon run log, which stayed after the fight - fixed on master, probe
   `dungeon_log_no_fight_text.gd` (red on the old code); and "Floor 2/5" on the starter dungeon
   (fixed 05992bee, also unreleased). And card rank-ups earned in a Warden (party) fight, including
   underground, were held until the party ended - v0.9.791's server only flushed them on item use and
   disconnect. Fixed d34ea3f0 (flush every resolved party round and at party combat end; dungeon
   party fights use the same two paths), probe `card_copies_visible.gd`, also unreleased.
   And the Warden kept joining the party of a player who ABANDONED Warden's Watch partway (any
   completed step read as "finished", and finished means "he walks you home") - and of every player
   who DID finish, outside posts, forever (nothing saved said he had left them home). Fixed on
   master, probe `warden_leaves_when_watch_ends.gd` (red on the old code).
   Owner, before this release too: the road width fix (item 6, roads 3 -> 2) and FEWER DOORS on the
   starter post; companion sprites that FACE the way they walk on the overworld and in dungeons
   (release held for it).
4b. **◐ PARTLY DONE 2026-09-15 (unreleased) - default UI scale at 1080p.**
   **THE HUD MOVED INTO THE MAP'S MARGINS (2026-09-15 night, unreleased).** Owner, over one
   screenshot round: overlays must hide when a menu like the inventory is up; the status wants a
   bordered panel like the others; the chatbox moves under the status panel and the action bar to
   the bottom of the screen; the chatbox needs Chat and System tabs; the players-online area
   shrinks to the column width so the game output grows vertically; the shortcut buttons move to
   the top of the right column; the status text can be smaller; the map sprites are hard to read
   at 1080p. All done (`121019c9`):
   - Coords, Area, minimap, the status panel (framed now, font 11 base) and the chat log all float
     in the ~300px margins either side of the map, placed against the map's measured width and
     each other's measured heights.
   - They hide over a page. Two things take the canvas and only one was noticed: a text page CLEARS
     it, a visual PANEL is just shown on top. Panels are matched by NAME (`*Panel` child of the
     canvas), polled in `_process`. Three separate things put them back a frame later - update_map,
     the minimap's own `visible = true`, and the travel row's default argument.
   - The bottom strip is the action bar, the input row and the player list, shrunk to that content
     instead of a quarter of the window: the canvas is ~120px taller. The INPUT ROW stayed at the
     bottom on purpose - it is how commands are typed, and a margin widget hides with the rest.
   - Chat has two channels with their own buffers and an unread dot; "system" is server broadcasts,
     hall-of-heroes, clan logins, bounties and anything the server sends as System.
   - `OVERWORLD_SPRITE_PX` 26 -> 32, which is what the tiles ARE (`_OverworldRoom.CELL`) - the old
     value was a 19% downscale from when the map lived in the side panel. **Bigger than that is
     upscaling**: nearest-neighbour is crisp only at whole multiples, so the next step is 64, which
     needs a smaller view. That is a gameplay decision (how far you can see) and is NOT done.
   - Shots harness: `worldpet` (overworld with a companion out) and `menus` (a page over the canvas).
   **SECOND ROUND, 2026-09-16 (`9220fd1b`, unreleased).** Owner asked what all this does to combat
   and dungeons - and a capture of each answered: badly. The status panel floated over the dungeon
   floor and the chat box over the combat log, because `_margin_widgets_shown()` returned true
   whenever the map was not eligible for the canvas, which is exactly what those modes are. Now:
   - dungeon / combat / Sanctuary are checked FIRST; the chat log RELOCATES to the bottom strip for
     them (a mode lasts minutes; a page over the canvas is a second) with a real minimum height.
   - the right column runs floor to ceiling: canvas, enemy bar, status row, action bar and input in
     a stack on the LEFT, MapPanel beside it. This broke three hard-coded
     `RootContainer/BottomStrip/...` lookups - one `_bottom_node()` finder by name now.
   - the column is TWO things: a pinned WHERE YOU ARE block (rebuilt each step, cleared on leaving
     the post) and a rolling log that scrolls with the newest at the bottom. The post block used to
     be printed by the client the instant a key was pressed and wiped by the server's location
     message a round trip later.
   - shortcuts ride in the travel row (falling back to the column top wherever that row is hidden,
     so they are still there underground); the player list is the third chat tab, tall and
     scrollable; the companion portrait wears the margin frame in its variant colour and is hidden
     underground; the dungeon KEY moved under the map with its avatar at tile size.
   - [x] **SEEN IN PIXELS 2026-09-19.** A `--shots=dungeon` capture taken while chasing a different
     question landed on the floor rather than in a fight, and the key is there and legible:
     `⌂ You  $ Loot  > Stairs  E Start  · Floor  & Node  × Trap  Sprites = Monsters  N Void whispers`.
     The renderer was always built (`_dungeon_key_text`); only the evidence was missing.
   - [x] **THE TEXT-PAGE OVERWRITE IS FIXED 2026-09-19 — and it was real.** `_ow_heal_canvas`
     exists to put the map back when a page clears the canvas, which makes it the one path whose
     whole job is to overwrite. It honoured a wide page and an open panel but **not
     `pending_continue`** - a screen waiting to be acknowledged. `_ow_canvas_eligible()` sounds
     like it would cover that and does not: it asks whether the map COULD own the canvas, never
     whether something is waiting. The length check only protects a page that printed MORE text
     than the map did, so a SHORT acknowledgement screen fell straight through.
     Probe: `nothing_paints_over_a_waiting_page.gd`, proven to fire.
     ⚡ **Two of my own errors are recorded in it**, because both are the recurring kind: I first
     talked myself out of the bug by reading a NEIGHBOURING function (`_margin_widgets_shown`) and
     believing it was the eligibility check; and the probe's first version matched the word
     `pending_continue` anywhere in the function, so the explanatory comment made a deleted guard
     still pass - the same comment-vs-call trap the healer probe hit hours earlier.
   - [x] **STALE, CLOSED 2026-09-19 — it has one.** `update_companion_art_overlay` builds its
     stylebox from `_margin_box_style()` and sets `border_color` to the companion's own variant
     colour, so every companion gets the same frame in its own colour. Confirmed in a live
     screenshot the same day. Was: *the companion art panel in the right margin has no frame.*
   **THE OVERWORLD MAP MOVED TO THE MAIN CANVAS (2026-09-15 night, unreleased), and took the
   Coords box, the Area box, the minimap, the status panel and the travel row with it.** Owner,
   after three attempts to win rows inside the side column: *"the map needs more space"*, then
   *"the Coords, Area, and Minimap boxes should be moved to the unused margins by the map"*, then
   *"we may even be able to move the status into a panel in those margins as well."* The map is
   square and the canvas is not - ~510px of map in a 1277px canvas - so there are ~370px of empty
   canvas either side. Both boxes, the minimap and `tool_status_overlay` (which is the whole
   status block; the StatusHUD VBox under it has been hidden for a long time) are anchored into
   those margins, measured from the map's own drawn width so they follow it when the tile size
   changes. The side column is now nothing but the log, which it had to be: the post description
   moved into it and that is eighteen lines.
   Two reported faults survived the first cut and were both found by MEASURING rather than
   reasoning, after a fix aimed at the wrong writer each time:
   - *"lines are still there"* - they were never line spacing. Measured off the owner's
     screenshot: 1-2px of #6A6250 at the ROW pitch, full width, vanishing under tall tiles. That
     is the `[url]` UNDERLINE (every map square is url-wrapped so it can be hovered for its area
     level). `map_display` has had `meta_underlined = false` since the figures went in and the
     dungeon renderer sets it false two lines before it draws; the canvas never did. One value,
     two places.
   - *"Crossroads still flashing in place of the map"* - the location handler was marked, and the
     post block is not in it. A trace on every canvas write (`--owtrace`, kept) named the writer
     in one run: the client redraws `_display_trading_post_ui` on EVERY step taken inside a post,
     and it opened with `game_output.clear()`. It goes to the side column now. The same step also
     ran `clear_game_output()` outside posts, blanking the map for a network round trip - gone
     too.

   ✅ The MAP fits now. The font was capped to fit ACROSS since v0.9.391 and never DOWN; in the live
   layout the map box is ~400 virtual px and the map wanted 506, so RichTextLabel scrolled and the
   middle - where the player stands - sat under the fold. The cap steps down using the font's real
   height at each size. The Tools/Status overlay grew at the full window scale (13 -> 19px at
   1080p) and every point came out of the map, so it grows at half that rate now (16px).
   Measured through a new `--uimeasure` flag on the running client, and the release gate asserts
   the fit at both live box heights. THREE instruments were wrong first: a headless probe laid out
   at 1920x1280; reading the font after `_ready` caught a transient; and `--resolution` changes
   nothing because the project stretches `canvas_items` from a 1920x1080 base, so layout is ALWAYS
   in 1080p virtual units.
   - [x] **THE DUNGEON SIDE PANEL IS CLOSED 2026-09-19.** Owner, after seeing the measurement:
     *"The dungeon panel should be fine now."* It is, and the numbers say why - the original
     report predates two changes that took the pressure off it: the dungeon KEY moved out from
     under it to below the map (2026-09-16), and the overworld minimap stopped drawing underground
     (2026-09-09), which had been occupying the bottom third of the column.
     MEASURED at 1920x1080, font 21, through the real builder with a full log of realistic
     **wrapping** entries:

         header + rule                       132px (fixed)
         a realistic log entry                44px  <- TWO rows; entries name an item with its
                                                      affixes and wrap
         full 10-line log                    572px
         at a 400px box   6 of 10 lines      at 500px   8 of 10
         at a 610px box  10 of 10 lines      <- the live dungeon height (measured 2026-09-10)

     ⚡ **It fits by exactly zero lines.** `DUNGEON_LOG_MAX` is 10 and exactly 10 fit; the cap and
     the panel height coincide by luck, not by design. The panel needs ~25 rows while its font is
     capped so a **21-row MAP GRID** fits, and underground that grid is not in this label at all
     (the floor is drawn on the canvas), so the font is chosen by a constraint from the other
     mode. That is why the guard stays even though the item is closed: release gate check
     `dungeon_panel_fits`, proven to fire (`DUNGEON_LOG_MAX` 10→16 gives `live_fit=false`,
     "10 of 16"). Anything added to that header spends a margin there is none of.

   - [→] **Needs an eyeball — AWAITING THE OWNER.** Nothing is blocked on code; it is a look-and-say,
      and the item says so. Original:  not a number: whether 16px Tools / the resulting map size actually
     look right to the owner at 1080p.
   Original report: *"We need to take a look at the initial UI Scale.
   1080p players ASCII map has to be scrolled to even see the middle of their map. The Tool panel and
   all of that is too big over there. Ideally they should be able to see their whole ASCII map by
   default."* And, same report from a live player: *"Their area on the right for where the dungeon
   text goes is pretty cramped as well, just like their map was."* - the dungeon side panel shares the
   column. Found in code so far: the map font is capped to fit WIDTH only (no height cap), and the
   Tools/Status overlay under it grows 1.5x at 1080p and squeezes the map from below.
   Measure first (a 1920x1080 client screenshot: map viewport vs map content, panel sizes),
   then set the default scale/layout so the whole map fits with no scroll; check the per-element
   resize system (memory: UI Scale system) so saved user scales are not clobbered.
4d. **✅ DONE 2026-09-15 (unreleased) - XP BY DANGER.** The XP formula
   scales a kill by lethality (hp + 2*str + def) against `expected_lethality = 50 + level * 10`,
   clamped to 0.7-1.4. That constant predates the calibrated monster curve. MEASURED
   (`tools/probe/xp_lethality_term.gd`, 60 real monsters at each of 11 levels): **every monster at
   every level clamps at 1.4**, so the term is dead - a monster six times deadlier than another of
   its level pays identical XP. The constant is 2.5x low at L1 and 75x low at L250.
   **Owner picked: tougher monsters pay more, AND the average kill pays ~15-20% more overall.**
   What the measurement already settles:
   - a monster's lethality within its own level runs **0.33..2.17x that level's mean**, so there is
     plenty of real spread for the term to read
   - the spawn mix sits at **1.09x (L1) to 2.56x (L1000)** of the calibrated curve's own `hp+2*str`,
     so a single constant against the curve would bias the whole progression; multiplying by the
     level's **mean species_power** (already in the curve file) cuts that drift to 0.63..1.26
   - the rest is that only low-tier species spawn at low levels, so "expected" has to be the mean
     over the level's **weighted eligible pool** (`select_monster_type`'s tier weights, bleed
     included), not over all 47 species
   **BUILT as `_expected_lethality(level)`**: the mean of that level's own weighted spawn pool (the
   tiers and weights `select_monster_type` draws from), each species costed through
   `compute_anchored_stats` - the function that builds a real monster - so it tracks the calibrated
   curve, the species power corrections and the flock division by itself, with no new hand-written
   number to go stale. The 7% tier bleed is excluded on purpose: a bled-in monster IS tougher than
   its level's normal fare and should be paid for it.
   MEASURED (80 monsters at each of 11 levels): the multiplier runs **1.30..2.10, mean 1.656**
   against the old flat 1.40 - the average kill is worth **+18.3%**, it varies at every level, only
   ~4% of monsters reach a clamp and no level's average sits on one. Kills per level move with it
   (L10 22.4 -> 18.3, L1000 16.2 -> 13.7). No refit needed - XP does not feed fight outcomes.

4c. **✅ DONE 2026-09-15 (unreleased) - two "what did that do?" gaps (owner 2026-09-15).**
   Home stone: the prompt and BOTH copies of the no-companion refusal now say it acts on the
   companion you have out and offers no picker. Egg listing: each picker row shows what the egg
   will fetch, quoted by `_egg_listing_valor` - the same helper that pays out (measured: Halfling
   tier-1 wolf egg quoted 229, paid 229; tier-6 gilded lich 29,899) - and the picker is rebuilt
   from the server's next character_update instead of the stale local copy that still held the egg
   just sold, which is why it read as if nothing had happened. `refresh_picker()` had no callers at
   all. Probe `tools/probe/egg_listing_tells_you.gd`.
   Original report: Both are the same shape - an action lands
   and the player is never told what it acted on or what they got. Cheap, and both sit on the
   onboarding path now that the Warden hands out a Home Stone (Companion).
   - **Home Stone (Companion)** acts on your EQUIPPED companion and gives no choice. Nothing says so:
     the prompt reads as though you are about to pick one. Name the companion it will send home in
     the prompt (and say plainly that it is the equipped one), or refuse with that sentence when no
     companion is equipped. Read the real flow before writing the text - `home_stone_select` /
     `home_stone_companion_response` in server.gd - the lesson written for the Warden's handout is
     the other surface to keep in step (one value, two places).
   - **Listing an egg on the market** never says what the egg IS or what it will fetch, and gives no
     confirmation that the listing went up. Show the egg's identity/tier and the price (or the
     suggested price) on the listing screen, and confirm the listing succeeded - through the
     pending-action pattern in CLAUDE.md's Player-Visible Output Rule, or the refresh wipes it.
   Check whether the missing confirmation is egg-specific or every market listing before fixing it
   at the egg.

5. **Shorter names for stacked affixes (owner 2026-09-15).** *"find a way to shorten those long names
   on items and monsters that have bunches of affixes. Ideally we just create new affixes or names
   for those that have a combination of multiple affixes, for example something that has juggernaut
   swift could have a single affix that instead combines those two, or even ones that combine 3 or 4."*
   Monsters: empowered mods prepend one prefix each (`monster_name = prefix + " " + name`, up to 3,
   plus variant and elite words). Items: affix prefixes/suffixes plus base and rarity words. Wants a
   COMBINATION table (two or three modifiers -> one authored word) consulted where the name is
   built, with the full list still readable on hover/inspect so nothing is hidden. Do it after the
   equipment audit (4), which may retire some affixes and change what needs a combined name.
6. **✅ FIRST-HOUR POLISH — COMPLETE.** Both remaining lines were already done and the list had
   not been ticked, which is the exact failure the rule at the top of CLAUDE.md exists for. Found
   2026-09-18 by opening them rather than trusting the line.
   - ✅ the Warden's handout — **DONE 2026-09-17**, full write-up further down; `"Rusty Weapon of
     Wisdom"` is `"Rusty Weapon"` and the kit is deterministic. Probe `starter_kit_plain.gd`;
   - ✅ DONE on master 2026-09-15: **"Floors Cleared: 2/5"** on the starter dungeon. Five places
     asked the dungeon TYPE (5) for the instance's floor count (2): HUD, floor messages, go-back,
     completion screen - and the **Floor Skip Charm**, which on the real boss floor spent the charm
     and skipped the boss to its final chest. One helper `_instance_floor_count` now. XP still
     divides by the type's count (owner: fix the text, keep the tutorial's pay). A refused charm is
     now refunded. Probe `instance_floor_count.gd`, proven red on the old code;
   - ✅ roads 3 wide -> 2 — **DONE 2026-09-15.** `ROAD_STAMP_OFFSETS` stamps a 2x2 block per
     waypoint (an even width cannot be centred on a symmetric plus), and `ROAD_HALF_WIDTH` is kept
     only so roads laid at the old width can be narrowed. The near-encounter-free corridor narrowed
     with it, as the entry required.
   - ✅ DONE on master 2026-09-15 - **give a Home Stone (Companion) at the end of Warden's Watch, and teach it** (owner 2026-09-15:
     *"have the player get their home stone companion at the end of the tutorial as well as let
     players know what it is for and how to use it"*). The reward is one line - chain bonuses
     already take `"home_stones"` (the Goblin King / Alpha Wolf chains use it) - but the lesson must
     be read off the stone's real flow (`home_stone_select` / `home_stone_companion_response` in
     server.gd), not written from memory. Fold it into the "An Egg" / first-hatch beats rather than
     adding a fourth panel. **Done that way:** a new character had ALREADY been getting the stone at
     creation since 2026-09-04 as a stopgap, untaught. It moved to the Watch's chain bonus (with the
     egg), and the first-hatch Companions panel teaches Register (survives death) vs Kennel.
     tutorial_walkthrough checks none at creation and one with the egg.
7. **One owner decision, then a small change:** should charm / weakness / slow on the monster be
   SHARED in co-op (see the open item below)? Today they protect only the member who cast them.
8. **The dungeon arc — the owner's big direction, and most of the list** (Phase 5 + the third
   owner-decision batch): dungeon rarity axes two and three (rolled modifiers, then rarer monsters
   / a guaranteed unique), dungeon-centred questing replacing the overworld quests, the Atlas as
   the hub, the dungeon card content. Onboarding already ends in a dungeon, which was that arc's
   stated prerequisite.
9. **The two accepted proposals nobody has built** (top of this file): trivial-encounter
   auto-resolve (full rewards) and post-to-post road travel (costs time and resources). Both are
   self-contained and good filler between arc pieces.
10. **Scrollback** (below) - retires the Player-Visible Output Rule's whole class of bug.
11. **LAST, by the owner's call:** the death curve runs the wrong way (end of file). Before that
    refit, answer the owner's 2026-09-15 question in numbers: *"do [the simulators] take into account
    the types of monsters players are running into where they can have a bunch of traits that stack
    on top of each other?"* From the code: the sim builds monsters with the game's own
    `generate_monster`, so species abilities, the +2 elite abilities, empowered mods (1-3) and
    variants appear at the rates the game rolls them - but its forced empowered/elite/boss cells
    multiply role stats ON TOP of a monster that may already have rolled its own empowered mods, and
    every audit reports AVERAGES. Nobody has measured the worst STACKS (e.g. a 3-mod empowered elite
    with death curse) separately. Add that cell before trusting a death-rate refit.

**Deferred, not forgotten:** Sanctuary menus revamp, companion type balance (needs the calibration
chain after it), party half two (independent movement + join-in-progress), controller support.

### ⚑ SMALL OPEN ITEMS LEFT BY THE 2026-09-15 WORK

- [→] **`assassinate_pct` now reaches the dice** (v0.9.790) — tracked in **THE BALANCE BATCH**
      (de-duplicated 2026-09-18; it was listed in two places under the same name).

### ⚑ THE STARTER KIT WAS NAMED LIKE ENDGAME LOOT — FIXED 2026-09-17

Was: `Rusty Weapon of Wisdom`, `Leather Armor of the Ogre`, `Mystic Cloth Helm`,
`Trollish Cloth Boots`, `Void-touched Wood Shield`, `Trollish Copper Ring`.
Now: **`Rusty Weapon`, `Leather Armor`, `Cloth Helm`, `Cloth Boots`, `Wood Shield`,
`Copper Ring`** — and deterministic, where before every new character got a different roll.

`get_starter_kit_item` ran the full affix generator, so the first item a player was ever handed
read like a raid drop. This mattered more after 2026-09-15, when the floor pieces gained per-slot
sprites: the player is looking straight at the thing.

**The entry's own warning was the design.** *"Do not rename without changing the roll ... a plain
name over rolled affixes puts a name on the item that its own stats contradict."* So the fix is a
real `plain` path in `_generate_item` that drops the affix roll **and** the rarity upgrade. Both
halves were needed: `_maybe_upgrade_rarity` can lift a "common" entry on its own (that is where
`Mystic Cloth Helm` came from) and common has carried ONE affix since 2026-09-03.

⛑ **AND DROPPING THE AFFIX IS A REAL LOSS OF POWER, NOT OF DECORATION.** At level 5 that single
affix is worth about as much as the item's entire base. Measured across all six slots (attack and
defence at full weight, HP at 0.2, stats at 0.5 — weights explicit, because summing raw stats
across kinds is what made an earlier measurement in this repo unsound):

```
  affixed at level  5   52.2      <- the old kit
  plain   at level  5   25.9      0.49x  - renaming alone would have HALVED it
  plain   at level 10   54.5      1.04x  <- chosen
```

So the level moved 5 → 10 and the kit sits exactly where v0.9.586 put it, with only the name
changed. Probe `tools/probe/starter_kit_plain.gd` samples 1800 draws (sampling, not one draw,
because the rarity upgrade fires on a minority of rolls and a single clean draw proves nothing),
reads the forbidden words **off the affix pools** rather than from a hand-written list that would
go stale, compares against the old behaviour by calling it (`plain=false` at level 5 is still
reachable) and checks that ordinary dungeon loot still rolls affixes — an opt-in path that
accidentally applied everywhere would have flattened all the loot in the game.

Not changed: `weapon_rusty` renders as "Rusty Weapon" because the name is derived from the type id,
and that type is the game's whole tier-1 weapon, used across the drop tables. Renaming it is a
separate job with wider reach than the starter kit.

### ⚑ ROADS ARE TOO WIDE — ALREADY DONE (2026-09-15). This entry was stale.

Owner 2026-09-14: *"the paths being 3 wide is a bit excessive, we should probably drop them down to
2 wide."* The entry said *"Not done"* and spelled out the open design question. **It was done the
next day** — `shared/world_system.gd` carries `ROAD_STAMP_OFFSETS` (a 2x2 block per waypoint) with
a comment quoting that same line, and `ROAD_HALF_WIDTH` is labelled *"the RETIRED three-wide plus;
kept only so old roads can be narrowed"*.

It even answered the question the entry raised. An even width cannot be centred on a waypoint with
a symmetric plus, so each waypoint stamps a 2x2: east-west reads as two rows, north-south as two
columns, and a diagonal stays two wide without the blobs a 3x3 square made at every turn. There is
a migration too — `narrow_old_roads()`, idempotent, because roads are SAVED as waypoints and
re-stamped every boot, so re-stamping narrower would never have removed the old edge and the live
world would have kept every existing road three wide.

Still worth a glance, since narrowing the road narrowed a **safe corridor**: path tiles carry a
halved encounter rate, and a tenth of it in Travelling stance. That is a balance change, not only a
cosmetic one, and it has not been measured.

⛑ **The third stale "not done" found today** — with the archived player-phantom design and
dungeon-centred questing. Read the code before working an item, not just the line. The rule already
in MEMORY.md (*"verify an item is not already built before building it"*) keeps earning its place.

### ⚑ SCROLLBACK — players cannot see what they just missed (owner 2026-09-14)

Owner: *"a chatlog or last menu history. Players often miss what was on the screen and don't have
anyway to go back to see what they missed on prior screens."*

**This is bigger than a convenience, and it retires a whole class of bug.** Measured:
`game_output.clear()` is called from **229 places**, against 3485 `display_game()` calls. Every
one of those 229 is a chance for something the player needed to read to vanish before they read
it — which is exactly why CLAUDE.md carries the **Player-Visible Output Rule** and its five-step
mandatory checklist (set a pending flag, add an action-bar state, add a bypass in the message
handlers, add an exit handler, add to the item-selection exclusion list). That checklist exists
because there is nowhere to look afterwards.

A scrollback buffer makes the checklist unnecessary for anything whose only requirement is "the
player must be able to read this". It does not replace it for things that must be read *at the
time* (a confirm prompt, a targeting step) — but those are a small minority of the 229.

Notes for whoever picks it up:

- The obvious shape is a ring buffer fed by `display_game()` itself, so nothing has to opt in and
  the 229 clears become harmless. Anything that has to opt in will be forgotten by the next
  feature, which is the failure mode the checklist already has.
- Combat already has a partial precedent: `_round_message_buffer` collects a round's lines for the
  condensed log. That is one surface doing locally what this would do globally.
- Chat is a separate panel (`chat_output`) and already persists; this is about the GAME output
  panel, which is the one that gets wiped.
- Worth deciding whether it is scrollback (scroll up in place) or a history panel (a shortcut that
  opens the last N screens). The owner said "chatlog or last menu history", which leaves it open.

### ⚑ THE SANCTUARY MENUS ARE DATED — owner 2026-09-14

Owner: *"We will need to revamp all of the sanctuary menus and systems at some point. Those
menu's and their controls are dated."*

Not started. Notes for whoever picks it up:

- The Sanctuary is the one screen EVERY player sees before they can play at all, and it is the
  last text-and-number-keys surface left in a game whose overworld, dungeon and combat are all
  sprite-rendered. `display_house_storage` paginates five at a time and drives everything off
  number keys, which is the shape the rest of the game moved away from.
- It crosses several systems, not one panel: storage, upgrades, the kennel, mastery headstarts,
  and the Door. A revamp wants a plan before code.
- Precedent to follow: the Sanctuary ROOM itself was already redone as sprites
  (`_render_house_room` / `_SanctuaryRoom`), so the visual half exists and the menus are what
  did not keep up.
- Equipment inspection landed 2026-09-14 as a stopgap (an Inspect toggle on the storage row,
  reusing `display_item_details`), because deciding what to withdraw meant withdrawing it to
  find out. That does not close this item.

### ⚑ COMPANION TYPES ARE NOT A CHOICE — owner 2026-09-14

Owner: *"we need to look at companion types and likely balance their power. Currently Tanks seem
to be the clear choice for everyone, we want some variety and real reason to choose."*

Not to be worked immediately, but do not lose it. Notes for whoever picks it up:

- **Measure before designing.** Get the actual pick rate and the actual contribution per type off
  live data or the simulator before touching a number. "Tanks seem to be the clear choice" is the
  symptom; whether it is HP scaling, the damage share, or the bonuses table is not yet known.
- This is a **player-power change**, so it invalidates `reference_monster_curve.json` — the
  speciescal → refcal → rolecal chain must run after it. See the top of CLAUDE.md.
- A global companion buff cannot fix a per-type gap: the chain holds win rate at target, so any
  across-the-board change is cancelled on the next refit. Only PER-TYPE changes survive.
- Tune to absolute targets, not to whichever type is currently weakest — see
  [[feedback_tune_to_targets_not_to_each_other]].

### ⚑ ONBOARDING ROUND 2 — owner test 2026-09-14, second pass

**Gear cadence, corrected by the owner 2026-09-14** (I had built it as three quest rewards):
*"You should get a couple of pieces of gear from the Warden, he teaches you how to fight then
teaches you about the world. He should take you to a starter dungeon that has all of the rest of
your starter equipment as floor loot in the dungeon."*

Built that way now — weapon + armour from him, helm/boots/shield/accessory placed on the starter
dungeon's floors, and a `world` lesson between the fighting and the dungeon.
`tools/probe/starter_kit_cadence.gd` executes the real slot map and fails if the two halves stop
adding up to a whole kit, so adding a gear slot to the game forces a decision about where it
comes from.




Fixed this pass (`bdd7060c`, `adef56ab`, and the party-kill/import commit):

Still open from that same report, in the order they block a new player:



### ⚑ ONBOARDING — fixed 2026-09-14, UNRELEASED, and one piece still open

Owner tested a fresh account locally and reported five things. Four are fixed on master
(`bdd7060c`, `adef56ab`), proven by `tools/probe/guidance_points_somewhere.gd` — every section of
which was verified by injecting its own fault.





**SUPERSEDED — v0.9.789 has been live since 2026-09-14; see the top of this block for the current state.** The notes below are kept for the deploy-verification detail. **v0.9.783 IS LIVE** (server hash-verified `074c338c`) - hunting grounds, and the danger guard
taught to read what actually spawns. **v0.9.782 IS LIVE** (server hash-verified `6def650b`, seven assets on the tag, Windows gate
passed, no script errors). It carries the blindsiding guard, the map level hover, and the
who-is-online feed. Next up in this block: hotzones.


**v0.9.781 IS LIVE.** Server deployed and verified by hashing the RUNNING process (`3d204cf9...`),
seven assets on the tag, Windows gate passed, no script errors. v0.9.780 shipped earlier the same
day (the dungeon grade lie, the world reshape, the lag, the one-time relocation).


### ⚑ OWNER DECISIONS 2026-09-13 (second batch)




### The two things left from the owner's 2026-09-13 list

1. [x] **HOTZONES — DONE, shipped v0.9.783.** Rich hunting grounds that relocate every 3 hours.
   ~~Original:~~
   *"hotzones don't serve much of a purpose anymore."* They were built when danger was uniform by
   distance; REGIONAL MENACE now does a lot of what they were for (dangerous country in
   unexpected places). The question to answer before writing code: what were they for, what does
   menace now cover, and what gap actually remains?
2. [x] **GATHERABLE ART — superseded.** The owner's multi-tile point reframed it: those pieces
   were 3x3 art squeezed into one cell, not bad art. Fixed at the cause. ~~Original:~~
   cause: `tree`, `bush`, `dense_brush`, `reed` and `mountain_herb` are all cut from
   `green_forest_v2`, so they are all the same green. tree vs bush is the worst - different JOBS,
   near-identical art. An automated search was tried and abandoned (alpha cannot tell a herb from
   a terrain edge); this wants `tools/tileset_contact_sheet.py <pack> --rows a-b` and an eye.

### Owed measurements, recorded rather than assumed away


### The lesson this session kept re-teaching

**A passing number is not a working feature.** Four separate times the assertions were green and
the thing was wrong, and only a PICTURE or an execution showed it:
- rivers scored "127 bodies, mostly small" while drawing a honeycomb of closed canals that would
  have cut the map into compartments;
- gatherable clustering "passed" because rivers were being counted as enormous stands;
- Scouting's vision bonus was written, exported and never called;
- the world had been striped along `7x + 13y` for its whole life, invisible until scatter thinned.

Render it, execute it, and make the control differ in ONE thing. See
[[feedback_indentation_is_invisible_to_a_source_probe]] and
[[feedback_verify_before_building]].

## v0.9.792 SHIPPED (2026-09-15 night) -- the equipment and item audit, and gear that reaches your cards

The owner's FULL equipment/item audit (backlog item 4), its fixes, and the tutorial faults a live
two-player session turned up. Everything here was MEASURED by executing the real code - two probes
were written for it (`tools/probe/items_in_combat.gd` uses every usable item three ways and fails on
a duplication, an unread buff name or a use that eats a stack; `tools/audit/equipment_audit.gd`
measures each gear stat against what combat actually reads) - and several first results were
instrument defects found and corrected before anything was believed.

**Items**
- An Enhancement Scroll used on gear at its enchantment cap DUPLICATED itself (a refusal re-inserted
  a scroll that had never been removed). Item duplication, on the market.
- One consumable resolver for every path (`drop_tables.consumable_effect` and friends). An item with
  no combat effect is refused and KEPT (owner's call), the client's combat menu asks the same
  question the server does, `inventory_use` mid-fight goes through the fight's rules, and refusals
  happen before the item is spent.
- Crafted Area Maps, Spell Tomes, Bestiary Pages, debuff/bane/heal-percent items became usable at
  all; crafted Rage / Forcefield / Power / Luck / Insight and the rest write buff names combat reads.
- Apex Sigil dropped as an affixed non-consumable that did nothing; one use of a stacked Escape
  Scroll / Compass / Ability Tome / Sigil deleted the whole stack; proc runes never procced; crafted
  armour and potions lost their rarity bonuses; crafted stats and Tempering were ignored; the three
  crystal runes could not be crafted. Reclaimer's Lantern, Elixir of Luck and the XP potions had no
  reader at all. Cursed Coin flips for loot or an elite (owner's pick).

**Gear and cards**
- Gear damage stats reach CARDS: damage_mult, crit damage, lifesteal/Shocking/Execute procs, and
  gear attack at ATTACK_CARD_SHARE 0.25 (owner: a reduced share so attacking keeps its place).
- Card-specific gear (`shared/card_gear.gd`) replaces the +N rank affixes: 15/30/45% power, cost or
  duration for ONE card, only the kinds that card measurably uses (`tools/probe/card_bonus_fit.gd`
  measures them and FAILS on drift). Old rank items convert; skill tomes are generated from the same
  table. Gear cost reduction caps at 75%; gear extra-turn caps at 30%.
- The "defense" buff was read TWICE per hit, as percent mitigation AND as flat defense, and Stone
  Skin wrote the wrong unit entirely.

**The live tutorial, with two new players on the server**
- A second new player's Warden led them to the FIRST player's private copy of the starter dungeon.
- Card rank-ups earned in a Warden (party) fight were held until the party ended.
- Fight text filled the dungeon side panel and stayed there.
- The Warden kept joining the party of a player who ABANDONED the Watch - and of every player who
  finished it, forever, outside posts.
- "Floors Cleared: 2/5" on a two-floor starter dungeon (fixed just after v0.9.791 was cut).

**Also**
- A kill in a party paid only the monster's base XP - four separate XP sums, one of which was not
  a sum at all. Every Warden fight, every co-op kill, and your companion's share with it.
- Sanctuary kennel: hover a companion for its card and art, Inspect for the rest.
- Hovering another player on the map shows their equipment tint and glyphs (it composed the portrait
  before their gear arrived and never redrew), and their companion shows the Companions card.
- Roads are two tiles wide, and the live world's existing three-wide roads narrow on boot.
- The starter post has four doors instead of fourteen.
- The equipment reference regenerates itself and reads rune sources from the recipes.
- Preflight's path-agreement gate measures 180 fights a side, not 27 (at 27 it failed one run in
  four on sampling noise alone).
- The monster curve was re-calibrated after the player-side changes (speciescal -> refcal -> rolecal).

**Carried forward:** companion sprites that face the way they walk (the source art has all four
directions; the original bake could not be reproduced pixel-for-pixel, so all four will be baked
together), the 1080p default UI scale, and the rest of the NEXT SESSION block.

## v0.9.791 SHIPPED (2026-09-15 evening) -- Warden's Watch can be finished, and party fights stop forgetting

Everything below shipped in v0.9.791 except the unticked items, which are carried forward in the
"SMALL OPEN ITEMS" list at the top of the NEXT SESSION block. The owner's local test round added: the
Warden plans a real route (`_escort_path`, BFS over `move_player`, tight -> wide -> through posts),
walks you home after the dungeon, stands on the real dungeon ground, and leaving a dungeon no longer
turns the player into a yellow "`" (the facing had been reset to "").

### The gold ring was usually not on the map (fixed in v0.9.790; its three gaps are now listed under SMALL OPEN ITEMS)

Owner, during the release: *"when it says to go to the gold ring will that actually be on the
players map or too far away for them to see it or behind an overlay?"* Measured by reading the
draw path: **no, mostly not.** The starter dungeon spawns ~30 tiles out (`_ensure_starter_dungeon_exists`)
against a sprite-map reach of 11 (fewer in fog/blizzard/sandstorm), and the client's off-grid
branch drew NOTHING - no edge marker - so the ring appeared only in the last ~11 tiles of the walk.
The Warden's stage-3 line "It is ringed on your map" was false whenever it was said, and the mark
lives only in client memory (lost on relog, 900s timer).

Fixed: an off-grid mark now draws a **gold arrowhead 4 cells from the player** pointing at it
(`overworld_room.gd` pass 4, `mark_arrow`); the Warden's line re-sends the mark before claiming it
and now says "gold marker". Probe `tools/probe/mark_arrow_offscreen.gd` renders and reads pixels
(with a reversed-direction control); release gate line `mark_arrow`.

**Still open, not done:**
- [→ carried forward to SMALL OPEN ITEMS] **Text-map fallback draws no ring or arrow at all** (sprite toggle off, or licence-restricted
      art missing from the build). Only the side-panel bearing helps there.
- [→ carried forward to SMALL OPEN ITEMS] **The ring can sit under the corner labels** (`coord_post_label` top-left, `RegionLabel`
      top-right) when the marked tile is in the top rows near a corner. Unverified in pixels.
- [→ carried forward to SMALL OPEN ITEMS] **Two unfinished starter dungeons could split the ring from the walk:** the mark is chosen
      once, `_escort_goal_for` re-picks every step. Inferred from code, not observed.

### The owner's live test of v0.9.790, item by item

**Shipped in v0.9.791** (probe `tools/probe/wild_swing_and_preview.gd`):

**Open, in the order they should be worked** (a blocker first, then the shared party-view cause, then
the teaching beats that depend on the Warden behaving):
- [→ carried forward to SMALL OPEN ITEMS] **Monster debuffs outside `_PARTY_SHARED_MONSTER_KEYS`** (`monster_charmed`, `monster_weakness`,
      `monster_slowed` + durations) are now carried PER MEMBER (before: dropped after the action). So a
      charm protects only its caster in co-op. Decide whether they should be shared - and if so, tick
      once per round, not once per member (see `_PARTY_DOT_KEYS`).
## v0.9.790 SHIPPED (2026-09-15) -- the live tutorial walkthrough, and what it turned up

Owner played the opening on the LIVE server and reported it beat by beat. Every item below is a
thing they hit, plus the causes found underneath. Released as v0.9.790, together with the off-map
guide arrow (see the NEXT SESSION block).

### The gold ring was drawn on the WRONG TILE, always

`_map_cells` renders `for dy in range(radius, -radius - 1, -1)` -- row 0 is NORTH and rows count
southward -- so the screen row of a world tile is `mid - (world_y - center_y)`. The client ADDED
it, which mirrors every marked tile about the player's own row. Owner's screenshot settled it: the
panel read "Wolf Den -- 1 tiles southwest" and the ring sat one cell NORTH, on bare road.

The Warden's own sprite offset carries this same negation, with a comment recording that it
shipped wrong once already. One fact, two copies, one of them fixed. The stage-one door marker had
been mirrored for its whole life too. See `tools/probe/guide_ring_and_delivery.gd`, which
re-derives the row order from `world_system` rather than restating it.

### THREE pop-ups became ONE, and none of them tells you to walk anywhere

Owner: *"some of the dialogue says to walk toward a ringed tile and highlights the whole map. It
shouldn't even be a line as the warden is supposed to walk you to the dungeon. There are like 3
dialogue things around there that should likely be condensed to one. The final one where it says
lead the way says I can move and he will follow instead."*

The three were the "Where You Are" world lesson, the "That one." dungeon pointer, and the escort
ask -- back to back, two of them instructing a walk the Warden makes for you, and the third under a
button reading "Lead the way" that reads as an instruction to the player. Now one panel: where he
is taking you, what the country is like, who does the walking, and a button that says
**Take me there**. `_point_at_the_dungeon` is now `_mark_the_dungeon` -- it rings the tile and
raises nothing.

### He delivers you ONTO the dungeon, and says how to get in

He used to stop one tile short. That single tile cost three things at once: the contextual [R] slot
only becomes the Dungeon button when you STAND on the entrance, the ring only clears when you stand
on what it marks, and the player was left guessing which of eight squares was the hole. Owner:
*"The new player will be lost and have no idea that they need to step on the dungeon tile and hit R
to go in."* Arrival is now a panel that names R and rings `action_4`.

### The walk itself was wedging, pacing, and restarting in silence -- four separate faults

1. **The step-two hand-off never ran.** `_escort_walk_start` was called from ABOVE
   `handle_quest_turn_in`, while the stage still said 2, so `_escort_goal_for` returned {} and the
   function fell out of its first `if`. The comment claimed it made the first step land
   immediately; it did nothing at all. A silent no-op that looks like the feature working.
2. **A post is a walled room and he walked into the wall.** Owner: *"when he was stuck he was in
   the post not walking into a door."* He now leaves by a door chosen for the JOURNEY
   (`here -> door -> goal`), **cached** in the walk state -- the first cut asked `_nearest_door`
   every tick and paced between two doorways: thirty ticks, every one a real move, net displacement
   ZERO.
3. **Once out of a post, stepping back in sorts last.** Greedy stepping has no memory; with the
   dungeon on the far side, the shortest step from just outside the door is back through the
   building. He left and re-entered forever.
4. **Pacing now counts as stuck.** The refusal counter only caught a walk that could not MOVE, so a
   greedy stepper against a lake shore sailed past it -- moving every tick, arriving nowhere, and
   never giving up. `ESCORT_DRIFT_TICKS` asks every 8 steps whether we got anywhere. Also: all
   EIGHT directions are tried in order of the distance they leave you at, not three; and a silent
   20-second restart now says something first (owner: *"he finally started walking again randomly,
   didn't notify me"*).

Measured in `tutorial_walkthrough`: 8 runs out of 8 now make real progress, from 3-in-4 before.

### The chat bar stole focus mid-tutorial

Owner: *"around step 2 being complete it focused the chat bar so I couldn't hit Q for my inventory
until clicking off of it."* The teaching modals were the only full-screen panels missing from
`any_popup_open`, so the very Enter that DISMISSED a lesson was seen again one frame later by a
`_process` loop polling the physical key. CLAUDE.md Pitfall #7, arriving through the chat focus
instead of the action bar. Both halves fixed: the modals suppress the polls while open, and
`_swallow_modal_dismiss_keys` makes the key have to be released first.

### Floor loot looks like the item now, not like its bucket

Owner: *"most floor loot equipment looks like a shield, one of the scrolls looks like a potion."*
Literally true -- the floor picked its sprite from `kind`, a GAMEPLAY category, and
`equipment.png` is a picture of a shield while `consumable.png` is a picture of a potion. 14 new
sprites (7 equipment slots off `Character.get_item_slot_from_type`, 7 consumable shapes), resolved
server-side by `_floor_loot_art` with the category kept as a fallback so an unknown item never
drops to a bare glyph. Bake recipe committed as `bake_floor_backed.py --rebake-loot`;
`verify_dungeon_art.gd` now fails the release if a key the server can emit has no art (958 lookups,
up from 713).

### Assassinate advertised a kill chance the game never rolled

Chasing *"Assassinate doesn't mention how much damage it will do if it doesn't kill on the card"*
found the bigger fault behind it. `assassinate_chance` carries a docstring promising it is the
single source "so the real roll, the live number on the card face and Analyze's report can never
disagree". They disagreed by a flat **13 points at every Read level** -- the 2026-09-08 rework that
made the strike always land wrote its odds as new constants at the ROLL site and left this function
computing the odds of the retired instant-win card. The roll also never read `assassinate_pct`, so
**Silver Tongue (+15%) and the unique that grants +20% moved the card and did nothing to the dice.**

Fixed structurally: `assassinate_chance` holds the lethal formula and the roll site calls it. The
roll is unchanged in power (2% + 3/Read, ~26% at a full stall); the DISPLAY moves down to the truth
and the two +assassinate_pct sources begin working as written -- a small, per-class power gain worth
a glance on the next `refcal`. The card now shows `~N | P% kill`, which also gives it the
bottom-left damage pip every other damage card has.

### Starter kit: a full pack used to eat it in silence

Answering the owner's question: yes, the starter dungeon has always paid up on the way out -- any
kit slot still empty when it is cleared is handed over. But `can_add_item()` was the WHOLE of the
handling, so a full pack meant the gear vanished with no message. `_grant_missing_starter_kit` is
now extracted, idempotent and re-askable: it names what it could not give, and walking into the
Warden afterwards hands over whatever is still missing.

### Housekeeping found on the way

- **The working tree was MIXED line endings** while `.gitattributes` says `* text=auto eol=lf`.
  Several source-reading probes bound a function body by searching for a literal newline + `func `,
  and in the mixed state that never matches -- so they silently extracted 103k characters instead of
  one function and reported nonsense. `new_character_starts_whole` had been red on master because
  of it. 84 files normalised; git sees no diff (it normalises both sides).
- **Five probes were red on master before any of today's work**, all stale assertions pinning text
  or behaviour that had deliberately changed: `warden_walks_with_you` (escort range),
  `tutorial_walkthrough` (he asks before moving), `guide_teaching` (three exact sentences from
  before the 2026-09-14 rewrite), plus the two above. All re-pinned to the current intent -- and
  where possible to a PROPERTY rather than to prose.
- **`card_vs_server` reports ~7 abilities whose card estimate disagrees with the server** by 3-8x
  (`magic_bolt` 0.12x, `meteor` 2.3x, `forcefield` 6x). Pre-existing, untouched, and worth its own
  session.

### Still open from this report

- Nothing outstanding from the owner's list. Released as v0.9.790.

---

## v0.9.789 SHIPPED (2026-09-14) -- the Warden walks you to your first dungeon

The onboarding arc, released. Everything from v0.9.788 to here was unreleased until tonight.

- **He LEADS you to the starter dungeon** rather than naming it and leaving you in the post.
  Owner: *"I shouldn't have to press anything. He should be leading/moving us too it."* The walk
  goes through the REAL `handle_move` with `escorted: true`, so terrain, gates and posts behave
  exactly as under the player's own hand; encounters are suppressed only while he is leading, and
  he rests the party before setting off. He leads from the FRONT (offset toward the goal) -- note
  world y is north and screen y is south, which is what made the first cut walk behind.
- **He asks first, and waits.** Owner, from a screenshot: *"He does start walking you but you have
  popups on the screen so you can't tell what's happening."* Teaching pop-ups now carry an `ack`
  the client returns when the panel closes, so the server can wait on a player instead of acting
  underneath them. Tutorials switched off means no pop-up can arrive -- the silence is a yes,
  otherwise they would be stranded at the post forever.
- **Busy hands pause him.** The walk did not know gathering refuses movement, so it asked three
  times a tick, every 450ms. Six refusals cancelled the walk and the next tick restarted it,
  re-announcing him and healing to full each time -- a full heal on tap. Also: arrival now records
  DONE (the stage stays at 3 until the dungeon is cleared, so arriving never stopped him), a wedge
  backs off 20s, and the rest is paid once.
- **The escort now ensures a starter dungeon exists** before promising to walk to one.
  `_point_at_the_dungeon` had done this since the pointer shipped; `_escort_goal_for` read the
  same world without it, so he agreed to lead and then stood still.
- **Type-vs-instance dungeon grade, retired at eight sites.** The owner's F4-shows-C5 report. The
  grade belongs to the INSTANCE; `_current_dungeon_tier` is now the single source, and the boss
  egg takes the dungeon's own rank as a floor.
- One escape scroll for every dungeon; admin rescue to the Crossroads; wish rewards state what
  they grant; the Trickster HP tax is gone; swift enemies split hits; Sanctuary equipment
  inspection; new characters are no longer born wounded.

### Two testing tools, because the replays were the real cost

Owner: *"setup a test scenario too where we are about to kill the third enemy in step 2. You're
exhausting me with all these failures and having to repeat the same steps."*

- **/admin -> Tutorial** jumps to a beat in Warden's Watch (step 2 one kill from the end, or
  step 3). It lands on a state a player could occupy -- `met_warden`, gear equipped, full health,
  teaching flags reset -- because a shortcut onto an impossible state makes the thing you went to
  test fail for a reason that does not exist in the game.
- **Six admin handlers rejected non-admins in total silence.** The account being tested on was not
  flagged admin, so every /admin button did nothing and looked unwired. That is how the evening
  started. They all say so now.

Probes: `tutorial_scenario_jump.gd`, `escort_asks_first.gd` -- both boot the real server and drive
real handlers; both proven to fire by injecting the fault.

**Still unjudged, and only a playthrough can:** whether the first fight feels dangerous, whether
all four floor pieces are findable, whether he looks right following, and whether the beats land
in a sensible order.

## v0.9.779 SHIPPED (2026-09-12) -- the resource economy, and the curve re-measured behind it

- `cost_percent` doubled uniformly (holds relative card pricing, so it does not re-open which
  card is worth casting). Casts per full bar 20.5 -> 10.6 at L20, 16.3 -> 13.0 at L100,
  14.5 -> 11.2 at L1000. Lowest resource in a fight 50-68% -> 26-47%.
- Rejected on measurement, not taste: the sim POLICY (it already spends max-affordable up to the
  ceiling, so it pays what the game charges) and `GEAR_COST_SHARE` (bites hardest at high gear,
  but the slack was worst at L20).
- Full chain re-run once each; 21 of 21 rolecal rows on target, 0 saturated.
- Room floor pool 7 -> 9 packs, 10 -> 13 baked tiles.

## v0.9.778 SHIPPED (2026-09-12) -- hover and click-to-inspect for people on the map

The last thing the overworld sprite arc still owed. Restored on `[url=]` + `meta_hover_started`,
the dungeon-entrance mechanism, because a composed image has no Controls to hang `mouse_entered`
off. `map_display` had hover connected and `meta_clicked` NEVER connected, which is why clicking
could not come back until this.

- `_show_map_tooltip` accepts a NULL anchor and follows the cursor.
- **The payload now names WHO is in each figure cell.** The first version re-derived the cell on
  the client with its own copy of the server's grid mapping - two copies of one calculation,
  failing as a hover that confidently names the wrong person. `_nearby_player_at_cell` is gone.
- `map_display.meta_underlined = false` - the url underline was slicing through the player and
  companion at knee height now that figures draw at 43px in a 26px line. **Found in a screenshot,
  not by a probe.**
- Three stale SOURCE-READING checks in `overworld_render.gd` deleted rather than re-synced: they
  broke on renames while the behaviour was correct, and both areas now have probes that execute.

## v0.9.777 SHIPPED (2026-09-12) -- the role layer, measured against the current player

- 21 of 21 anchor rows on target, none saturated. L1 str_mult 3.79->7.08 empowered, 3.48->7.80
  elite, 2.76->5.62 boss; mid and late game down 17-50%. An elite at L1 had been won 99% of the
  time against a 40% target.
- `passes` 6 -> 12 in rolecal, because the L1 rows were SATURATED at the clamp and looked
  converged. See [[feedback_saturation_is_not_convergence]] / the NEXT SESSION block.
- **The release gate now proves the packaged build carries the curve.** It is DATA, so every
  freshness probe passed on a build that had lost it, and monster_database then silently reverts
  to legacy base_level scaling. Proven by injecting the fault. That injection also caught a check
  of mine that could not fail - `role_multipliers(...).is_empty()` reads false with the curve
  gone, because the fallback returns a well-formed dictionary.

## v0.9.776 SHIPPED (2026-09-12) -- the minimap could not see most of itself

- **The range bug the owner reported.** `_minimap_cells` draws +/-40 by +/-20 tiles; the dungeon
  list it was handed came from `get_visible_dungeons(x, y, vision_radius)` - radius 11. Six
  sevenths of the picture could never show a dungeon. Both are sized off `MINIMAP_REACH` now, and
  the duplicate `const MAP_HALF_W/H` inside the function are gone.
- **6.9ms -> 0.9ms per move** (walking 8.9 -> 1.4). Sample lattice snapped to world coordinates
  so a per-cell glyph memo can hit at all, keyed by world coordinate so it is shared by every
  player, invalidated by `chunk_manager.tile_revision`. Markers scattered rather than gathered.
- **The companion trails again**, in the cell its owner stepped out of, picked from facing.
- **Figures compose at 1.35x** into their own cache, so scaling a figure cannot scale a tile.
- **A spent gathering node in a HOTZONE** was identical to a full one - both reported `!hot:`.

## v0.9.775 SHIPPED (2026-09-12) -- the square you stand on was empty

774's fix never ran. `client/overworld_room.gd`'s figure block was indented into the branch that
is skipped exactly when there is a figure, so the composed map drew the ground, the tiles and the
markers and no people at all. Dedented to the body of the cell loop.

- `tools/probe/overworld_render.gd` gained a PIXEL comparison of the centre cell, with a control
  that supplies a figure entry naming no sprite (so the marker is suppressed on both sides).
  Verified to fail on the re-injected fault.
- Verified in the RUNNING client via `python tools/test_setup/shots.py world` before the release,
  not only in the probe. That is the whole reason this one is right.

## v0.9.774 SHIPPED (2026-09-12, same night) -- the figures were in the wrong place

Four reports from the owner's first play of v0.9.773, and THREE OF THEM WERE ONE CAUSE.

**The cause.** `_sync_map_sprites_overlay` still drew the player and companions over the map,
placing them from FONT metrics - character width times two, the font's line height, a sprite size
derived from the font size. That was right when a map cell was two text characters. It is
meaningless over a grid of 26-pixel images.

So the player stood about a row off; and because a player judges everything against where they
see themselves, the STATIONS in a post read as one square too low (*"I have to try to walk into
the space above them to interact"*) and gathering nodes looked out of line. The companion was a
bare letter (*"just showing a K"* - Kelpie). And the player did not grow with the post zoom,
because the overlay never knew the cells had changed size.
**Fix: the overlay stands down when the map is art**, returning before it computes a single
metric. The figures are already composed into the image at the right square and the right scale.

**The post zoom is GONE, and that is a measurement correcting a guess.** It shipped as "crop to
the middle 11, draw them twice as big", on the assumption that you cannot see past a post's walls
so the edges were spare. Measured after the report: **a post is 17-20 tiles across in a 23-tile
view.** There was nothing spare, and the crop was cutting off the walls and the DOORS - *"The
post doesn't seem to have obvious doors, seems like you have to walk out and in through part of
the wall."* A post still reads as a room because it stands on its own floor, which was the half
of the idea that worked.

**A harvested node now looks harvested.** The text map dimmed a spent node to a grey comma. The
sprite map drew the tile and then looked for an overlay called `depleted` that was never baked,
so a used-up ore vein was pixel-identical to a fresh one - *"not sure if they are clearing
properly once I get them."* They were clearing; they did not LOOK it. Depleted cells dim now.

**Client-only: the live server binary from v0.9.773 is still correct and was not redeployed.**


## v0.9.773 SHIPPED (2026-09-12) -- the overworld is drawn, and dungeons belong where they stand

Twenty-one commits. The whole overworld sprite arc and the whole dungeon arc, in one release.

**The map is art.** All 67 overworld tile types and all 7 map markers cut from the Raven packs -
every gatherable, six biome grounds, water, roads, walls, the post stations and every piece of
post decor. `client/overworld_room.gd` composes the grid into one image and the client draws
slices of it; you, other players and everyone's companions are figures wearing their variant
tints; a post crops to its middle at double size and reads as a room on its own floor. A setting
turns it off, and every failure falls back to the text map, because the art is licence-restricted
and not in git.

**The map on the wire.** `build_map_payload` is the single implementation and the display string
is that payload inflated, so text and sprites cannot describe two different maps. 28.2 KB a step
became 5.2 KB. A golden of 21 views captured BEFORE any of it guards that the text form never
moved.

**Dungeons.** Grade is now a reading of the land rather than a number on the type, which fixed
the owner's G2-in-L15-country report and made an A5 Goblin Dungeon possible at the same time.
200 dungeons became 3,000 spread over the whole world instead of its middle 4%, affordable
because they are indexed by position - a map query went 117us to 1.8us. Types have a rarity at
last (`spawn_weight` had been authored and read by nothing). A dungeon holds more than one
species. Floor eggs follow the dungeon's rank AND what actually spawned in it. Entrances can be
hovered. Markers stop building interiors nobody enters. Personal dungeons get cleaned up.

**Companions.** One ladder for grade and rank drives health, damage, abilities and the bonuses
granted - an H9 had been three times tougher than a G1. `speciescal` and `refcal` were re-run
after it; `rolecal` was not (see NEXT SESSION).

**Fixes.** The three hover faults, two of which were one cause. Variant tints on sprites
everywhere. Two server loops that made a step cost twice what it needed to.

**What is NOT yet checked in play:** all of it. Nothing here has been played, and the playtest
queue items 11 and 12 are the list.

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


## ⚑ THE ORDER — sequenced so nothing gets built twice (recounted 2026-09-11)

**Live count 2026-09-13: 44 open, 122 done** (counted off the `- [ ]` boxes, which is the only
count that cannot drift). The prose figures below are the 2026-09-11 snapshot and are kept for
the reasoning, not the arithmetic.

Owner: *"How many items do we have left? Let's tackle them in an efficient order so we avoid
recreating work."* Counted after ticking 11 items that were resolved but never checked off:
**54 open across 15 arcs, 72 done** — recounted the same day at **47 open (43 + 4 partial)** after ticking seven room-pass entries that v0.9.768 had already shipped. The order below is dependency-driven, not preference —
every "before" below is a case where doing it the other way means redoing the first piece.

**0. CUT THE RELEASE. — ✅ DONE 2026-09-11, shipped as v0.9.771 then v0.9.772.** Was a gate, not
   an item. **Five open items could not progress without live data** — watch the five characters at L25+, feel-check the rest change, the "party play isn't
   working" repro, the dungeon-level mismatch second example, and the dungeon-depth confirmation.
   **The "party play isn't working" repro is CLOSED (2026-09-13) and never needed live data:** the
   owner named it as no dungeon support plus a wish for independent movement, and the code
   confirmed the first half outright. It is now the "PARTY PLAY IN DUNGEONS" design item.
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






- [→] **Watch the five live characters at L3-L12** — moved to **THE BALANCE BATCH** (2026-09-18).
      Still worth saying here: at L25+ re-validate `make_char` against real saves; at L50+ the
      high-level balance work can finally be checked against real data.
- [→] **Feel check the rest change** — moved to **THE BALANCE BATCH** (2026-09-18).

## Phase 2 — balance follow-through (cheap audits, no chain)

- [→] **Sage / Barbarian / Ranger death per encounter** — moved to **THE BALANCE BATCH**
      (2026-09-18).
- [→] **The high-level win targets predate retreat** — moved to **THE BALANCE BATCH** (2026-09-18).
      Kept here because it explains the instrument: `refcal` REPORTS death rate but cannot steer by
      it — at a ~0.3% target there is under one expected death per sample, so there is no signal to
      correct against.

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





- [→] **AWAITING GITHUB: garbage collection of unreachable objects.** Request SUBMITTED <!-- audited: 2026-09-19 --> Re-marked: BLOCKED ON GITHUB, nothing to build here.
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


- [~] **PARTLY DONE 2026-09-11.** Written and committed: `bake_landmark_tiles.py`
      (tile_floor32, with a fragment test that refuses half an object), `bake_glyph_tiles.py`
      (the glyph tiles, with a font-coverage assertion that refuses to bake a missing-glyph box)
      and `bake_egg_variants.py` (the variant->egg table, as a collision-free assignment).
      STILL MISSING: `prop_floor32` (11), `free_floor32` (5) and `egg_floor32` (100). Those three
      remain irreplaceable data.





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



## Phase 2.95 — SPRITE THE OVERWORLD (owner direction 2026-09-11)

Owner: *"the more I think about it the more I wonder if we can just do sprites for the entire
overworld? ... How will it effect server and client performance? How will it impact the number
of supported players on the server at once?"*

**RE-MEASURED 2026-09-11 against the REAL server world, and it overturns the plan below.**
`tools/audit/overworld_render_cost.gd` builds a live chunk manager and calls the real
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
      nothing. **PHASE 2 IS DONE.**
      (The old "monster figures on the overworld" line was wrong: the overworld never draws
      individual monsters, only hotzones, so there was nothing there to sprite.)
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





- [~] **LIKELY SOLVED 2026-09-11, awaiting one confirmation.** Almost certainly the same cause as
      the bossless dungeon and the re-farm: the owner was re-entering a personal instance that had
      already been completed, which KEEPS its original sub-tier and skips the whole
      `if instance_id == "":` branch — and that branch is where the sub-tier inherit lives. So the
      tile advertised its own depth while the instance kept the one it was born with. Completion
      is now stamped on the instance, so a finished run can no longer be re-entered.
      The entry diagnostic is still in place; confirm on the next fresh dungeon and close it.



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



## Phase 3.45 — SPRITE INTERIORS (owner direction 2026-09-10, NOT previously captured)

Owner, on buying the Raven Fantasy collection: *"I eventually would like to make inside of posts,
player sanctuary, and player posts use sprites. Not sure how feasible that is though since it
would require our overworld to consist of sprites as well as the current ASCII."* And on the
dungeon split: *"keep our dungeon corridors using what we currently do but make all of the actual
rooms out of sprites from those packs."*

This was discussed across two sessions and never reached the list. Recording it because the packs
are now bought, unzipped and licence-cleared, so the blocker is design rather than assets.

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

- [→] **The brightness gap may be a FEATURE, not a defect.** darkcave sits at value 0.45; most <!-- audited: 2026-09-19 --> Re-marked: an OPEN QUESTION for the owner, not work.
      Raven packs are 0.57-0.66. Rooms would read as brighter than the corridors leading to them
      — which is what a lit room off a dark passage should look like. Decide deliberately whether
      to lean into that or flatten it; do not correct it by reflex.

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
- [~] **MORE PACKS DONE 2026-09-12 (7 -> 9, 10 baked tiles -> 13). MULTI-TILE DECOR still open.**
      `tools/scan_room_floor_candidates.py` is the missing half of the bake script: it applies
      that script's OWN gates (imported, never restated) to the twelve packs that were unzipped
      and unused, ranks by texture and renders every survivor beside the wall rim.
      It produced 40 candidates and **the render threw most of them out**, which is the step the
      bake script warns cannot be skipped: most survivors were solid palette SWATCHES (pure teal,
      black, white) and the textured ones were roof tiles, tree trunks, planks and shadow.
      `beach_ocean_and_shore` reproduced the recorded trap word for word - its best textured
      candidate is WATER.
      Added: **`miners_cave`** (two variants - speckled cave rock and mauve stone, the most
      dungeon-appropriate art in the whole set) and **`red_rock_desert`** (sandstone paving).
      Both pass the bake's wall and corridor gates and were looked at as room blocks against the
      rim. `tools/probe/room_pack_pool.gd` holds the hand-written `ROOM_PACKS` list against the
      baked FILES in both directions - a pack listed but not baked draws nothing, a pack baked
      but not listed is art no player ever sees. Was: **More variety when it is wanted: the OTHER packs, and MULTI-TILE decor** (owner,
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







- [→] **Where is the SEAM?** A room entrance is a hard transition between two packs in adjacent <!-- audited: 2026-09-19 --> Re-marked: an OPEN QUESTION, not work.
      cells. Options: a doorway/threshold tile from the room pack that reads as belonging to
      both; a one-tile border of rubble; or accepting the cut. Needs to be looked at on screen,
      not reasoned about — the same way the prop occlusion question was settled.

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

- [→] **CRT / scanlines — A PROPOSAL AWAITING A YES/NO, not accepted work.** Nothing exists and
      nothing is blocked; the line is my own suggestion and says so ("I would not do it first").
      Marked distinctly so the list stops counting my ideas as the owner's backlog. Original:
      **possible, but I would not do it first.** A `ColorRect` overlay with a
      scanline shader is straightforward and the pattern above shows how. Two honest reservations:
      the game is TEXT-HEAVY, and scanlines over a combat log or a side panel cost legibility for
      atmosphere; and at a 64px tile on a 1080p screen the effect is subtle enough that it may not
      repay the cost. If done: scope it to the DUNGEON CANVAS only, never the whole window, and
      ship it off by default as a setting.
      The GameMaker documentation the owner found is a `.pdf` with subset-encoded fonts - its text
      could not be extracted - so it is a reference for the LOOK, not a recipe to port.

## Phase 3.5 — input and accessibility (owner direction 2026-09-10)

Owner: *"we need to add support for players with no numpad on their keyboard. With no numpad they
will have a hard time moving through the world... Ultimately it would be great if we had some type
of controller or phone support as well."* A 2026-08-20 playtest had already recorded that
"non-numpad keyboards need an answer at some point"; it was never written down anywhere actionable.



- [ ] **THE VALOR ECONOMY, REALM-WIDE — owner direction 2026-09-17.**
      <!-- audited: 2026-09-19 --> Verified still open: only STEP 1 (source enumeration) is
      ticked, and `QUEST_VALOR_PER_LEVEL := 3.5` is still the interim anchor the item exists to
      replace. The DONE-words that flag it belong to step 1 and to a live bug it found on the
      way. Original:** Asked to pick a target
      for quest valor, the owner answered: *"I'm okay with this but honestly valor costs for
      everything likely need rebalanced across the realm. Some things aren't even actively
      balanced or used as far as blacksmiths, healing, repairs, etc."*

      ⛑ **SO THE QUEST NUMBERS SHIPPED IN v0.9.802 ARE AN INTERIM ANCHOR, NOT AN ANSWER**, and
      `QUEST_VALOR_PER_LEVEL` says so in its own comment. They were calibrated against the sinks
      that exist today — cheapest Sanctuary upgrade 250, ladder to 8000 — which is exactly
      the set the owner has just said is wrong. Re-deriving them is part of this item, not a
      separate one.

      ☑ **STEP 1 STARTED 2026-09-17 (source enumeration only — no runtime yet).**
      **45 `add_valor` sites against 26 `spend_valor` sites**, which supports the owner's instinct
      — but the raw counts are the WRONG UNIT and should not be quoted as a finding: a market
      sale TRANSFERS valor between two players and a refund REVERSES a spend, and neither mints
      anything. The classification into mint / transfer / refund is the actual step 1 and is not
      done.

      ⛑ **TWO SINKS ARE HIDING INSIDE THE FAUCET.** `add_valor(account_id, -price)` (12446) and
      `add_valor(account_id, -GUARD_HIRE_VALOR_COST)` (29720) spend by adding a negative. That
      matters beyond bookkeeping: `spend_valor` returns false when you cannot afford it and
      `add_valor` has no such check, so these two can take an account NEGATIVE. Worth confirming
      before the pricing pass, because a price that can overdraft is not a price.

      ☑ **AND IT FOUND A LIVE BUG — FIXED.** `add_valor(peer_id, hoard_valor)` passed the int
      peer id where `account_id: String` was expected, so the **Ancient Dragon Lair's gold-hoard
      tile paid nobody** while cheerfully printing *"+7 Valor"* to the player. Both sibling tiles
      (SCATTERED_LOOT, TRINKET_PILE) did it correctly; this was the odd one out and the biggest of
      the three payouts. Found by a static scan for valor calls whose first argument is not
      account-shaped — it flagged exactly two sites and cleared the other.

      What the pass has to cover, in order:
      1. **Enumerate the sinks and measure which are ever used.** Blacksmith repair, healer,
         recharge, home stones, bounties, Sanctuary upgrades, clan vault, duel stakes. The owner's
         claim that some *"aren't even actively balanced or used"* is the thing to verify first —
         a sink nobody uses is either mispriced or unreachable, and those are different fixes.
      2. **Enumerate the FAUCETS and measure them per hour of play.** Quest turn-ins, floor-loot
         coins, corpse sacks, sales. The owner is sitting on **62.4K valor at level 10**, which is
         the tell that faucets already outrun sinks badly.
      3. **Then set prices against a stated target** — how many hours of play one Sanctuary
         upgrade should cost — rather than against each other. (`feedback_tune_to_targets_not_to_each_other`.)

      ⛑ Do NOT start by raising prices. A currency nobody spends is a sink problem, and
      inflating costs against a 62K balance changes nothing for an established player while
      pricing a new one out entirely.


- [→] **⛑ CONTROLLER — AWAITING A PAD IN A HAND, not code.** The wiring exists and is verified
      (`InputEventJoypadButton`, `PAD_ACCEPT`, `PAD_FOCUS_BAR` are all live in client.gd); what
      cannot be verified without hardware is the FEEL. Marked as owner-action so it stops reading
      as unstarted work. Original note: **NOT ONE KEY HAS BEEN PRESSED ON A REAL PAD.** `Input.get_connected_joypads()`
      was **empty** for every measurement above. Everything is verified by injected events and by
      reading the InputMap, which proves the WIRING and says nothing about the FEEL: whether the
      move cooldown suits a held stick, whether the deadzone is right, whether Back-to-focus-the-bar
      is discoverable, or whether a diagonal is comfortable. That needs a pad in a hand.
      Was: Godot has joypad input built in; a D-pad or stick gives all
      eight directions natively and the face buttons map to the action bar. Scope it as its own
      piece. Note `_on_move_button` already exists as an orphaned 8-way handler with no caller —
      an on-screen pad that was built and removed — and it is the natural target for both a
      controller cursor and touch.

- [→] **Phone / touch (LATER, its own arc).** Needs a mobile export preset, a touch UI, and a <!-- audited: 2026-09-19 --> Re-marked: DEFERRED by the owner to its own arc.
      layout rework — the three-panel desktop layout does not survive a phone screen. Much larger
      than the other two; do not start it inside another arc.

## Phase 3 — combat UX debt (visible to every player, every fight)






















## Phase 4 — party (half-built; finish or cut)

- [→] **Watch-a-teammate's-minigame** — **OPTIONAL, moved to the END of the backlog** (owner,
      2026-09-18: *"Minigame watch is an optional, it can go to the end."*). `Watch` in the player
      menu already follows another player's game output; this is only the narrower live-minigame
      case.


- [ ] **COMBAT IS NOT INTERESTING ENOUGH - bring in ARPG / survivor-style elements. Owner direction 2026-10-22:** "I'd like to find a way to make our combat include more elements that ARPGs or Survivor type games do. Combat isn't interesting enough overall. I like having strategy but my favourite games are Survival Crafting games and ARPGs." No example game does it, so this is DESIGN-FIRST: a written proposal with the owner before any code. Candidate axes to put to the owner: build-defining proc/trigger gear and path nodes that change HOW a card plays (the Signature branches are the first step), enemy telegraphs the player answers (the 24 cyclical bursts), in-fight pickups/choices between rounds (survivor-style level-up picks), and loot that visibly changes the deck. Sits in Wave 1 beside the dungeon card power pass, because it decides what those cards ARE. ANSWERED 2026-10-22: the whole loop feels repetitive; keep the existing build layer. PROPOSAL + owner answers in `docs/design/combat_loop_variety.md`: order = (1) card tags + combat event bus + gear/path TRIGGERS (owner's pilot pick), (2) telegraph queue then an optional real-time timing window (R1), (3) PERSISTENT boons - RUN RULE SETTLED 2026-10-22 (design doc section 10): life boons last the whole life, no cap but diminishing stacking, lost on death; plus stronger dungeon-only boons; guaranteed after hard fights, chance after normal ones; needs a life-build model in the sim, (4) waves in dungeons. **Step (1) BUILT 2026-10-22, unreleased:** card tags + six combat events + eight effects + 13 triggers (`shared/combat_triggers.gd`, probe `combat_triggers_fire`), carried by epic+ chase gear (design doc section 11). **Ascendant tier BUILT 2026-10-22** (27 trigger-bundle nodes at L500/2000/6000, probe `ascendant_nodes_fire`). **Timing window (R1) BUILT 2026-10-22** (design doc section 12). **Step (3) PERSISTENT BOONS BUILT 2026-10-22** (design doc section 13; probe `boons_core`; sim `--boons=` + `boonvalue`). STILL TO DO: uniques, party-fight support, step (4) waves, then `preflight` and the ONE Wave 2 chain with `--boons=typical`; `pathgap` re-run at L500+ DONE (all classes within +-10pp of the median, CLASS_SCALE unchanged). **WAVE 2 CHAIN RAN 2026-10-23 with `--path=typical --boons=typical` (commit 94622670; monster HP x2.5 at L1 to x23 at L10000; L10000 boss role 11/12 knobs clamped; death 5.1% at L2500/L5000 at n~118, unconfirmed). Per-class changes then applied (a60d2f1a): CLASS_SCALE Fighter 1.3 / Barbarian 1.45 / Paladin 0.9 / Wizard 0.75 / Grifter 1.05 / Ninja 0.65; dungeon-card scale Wizard 4.5 / Grifter 3 / Ninja 2 (`dungeoncardswap` PASS). The curve was fit BEFORE those class changes, so it needs ONE more chain run to be current. `refval`'s ratio column compares against `shared/reference_player_curve.json`, last written 2026-09-02 (before the level_up/path/boon player fixes), so its L5000/L10000 drift is a stale input, not a game fault; `-- refcurve` regenerates it but also moves the companion own-level HP anchor (character.gd reference_player_hp), so that is a gameplay decision.**
- [ ] **PATHS NEED A REVAMP — CLASS-SPECIFIC AND LESS CONDITIONAL. Owner direction 2026-09-18:** <!-- audited: 2026-09-19 --> Verified still open: `shared/path_database.gd` holds exactly three trees, keyed `"warrior"`,
      `"mage"`, `"trickster"` — per-ARCHETYPE, which is precisely what this asks to change.
      *"Path's need revamped and should be class specific and less conditional."*
      **2026-10-21 DESIGN DRAFTED: `docs/design/paths_revamp.md`** (ranks, feats, Signature branches per class, limited respec,
      and section 8: the instruments to build so paths close the per-class gaps - path spec in the sim, pathfires, pathvalue,
      pathcurve, pathspread, pathgap). Owner approved the node drafts. Build order: data model -> wiring -> instruments ->
      per-class values -> the ONE Wave 2 chain.
      **BUILT 2026-10-21:** data model (ranks, point curve, feat ladders, limited respec, ranked panel) + the Signature branch for ALL NINE classes, each node
      proven by a probe (`path_ranks_and_feats`, `path_nodes_are_wired`, `*_signature_fires`). **BUILT 2026-10-22:** the six new archetype branches (45 nodes, probe
      `archetype_branches_fire`, panel shows them as two rows of three) and the two owner-approved fixes (Assassinate keystone now reaches cards with both halves;
      a slowed monster now hits less; probe `assassinate_and_slow`). **BUILT 2026-10-22:** the instruments (`pathspec`, `pathcurve`, `pathfires`, `pathvalue`, `pathspread`, `pathgap`; `--path=` spec in `make_char`),
      six defects they found fixed (see design doc slice 7), and the per-class value table (`CLASS_SCALE = {"Paladin": 1.5}`). high-level reach and the feat ledger are built (model-only above L91: no live character is higher); Ranger crit nodes pay as card damage. PATHS ARE DONE except the Wave 2 chain, which waits for the other Wave 1 power inputs. Known gaps: party (co-op) fights do not run the card-damage nodes or
      cast riders; Paladin ally-heal for a human teammate needs the party card path.

      Two distinct complaints, and they pull in the same direction:

      * **Class-specific.** The trees are per-ARCHETYPE today — 54 nodes across three trees
        (`project_skill_tree_design`, shipped v0.9.654), so all three mage classes share one path
        tree. That is the same shape the class ENGINES were taken out of on 2026-09-07, when
        "one engine shape per archetype" became "one per class" for exactly this reason: an
        archetype-wide system cannot express what makes a Sage different from a Sorcerer, so it
        ends up generic and every class in the archetype picks the same nodes.
      * **Less conditional.** A node whose effect only fires in a narrow circumstance reads as
        dead weight at the point of choosing, which is where the decision actually happens. This
        is the `overload` lesson from the card work: a conditional a player cannot evaluate is
        not a choice, it is a trap.

      **⛑ Do NOT start by writing nodes.** Read the 54 that exist first and classify them by how
      often their condition is TRUE in a real fight — the simulator can answer that, and the
      answer decides whether this is a rewrite or a pruning. Writing replacements before
      measuring the existing ones is how the last three content passes produced work that had to
      be redone.

      **⛑ THIS IS A PER-CLASS POWER CHANGE, so it belongs to a BALANCE BATCH window** (see
      "THE BALANCE BATCH"). Schedule it to land with the same-level death-rate work: both are
      per-class, and per-class is the only kind of change that survives a refit — a global buff
      is cancelled by the next one. One chain run should cover both.

      Prior art to read before building: `project_skill_tree_design`, `project_engine_shape_per_class`
      (why archetype-wide became per-class), and the card roster work in `project_card_arc_2026_08_27`.

- [→] **COMBAT TACTICS / GAMBITS — owner direction 2026-09-18, INTERESTED not committed.** <!-- audited: 2026-09-19 --> Re-marked: a PROPOSAL - owner said INTERESTED not committed.
      *"Another thing I'm interested in is possibly setting up AI like tactics for combat where you
      can set what your character should do each turn (kind of like Final Fantasy XII's Gambit
      system, or siralim ultimate)."*

      A player authors an ordered list of **condition → action** rules and the character acts on
      the first match. FF XII: a short list of purchasable gambit slots, each `target/condition`
      paired with an action, evaluated top-down. Siralim Ultimate: the same idea taken much
      further - per-creature, many conditions, and deep enough that building the list IS the game.

      **⛑ WHY THIS IS A BIG DECISION AND NOT A FEATURE.** It changes what combat IS. Today every
      round is a live choice from a hand of cards, which is what the card arc has been built
      around; a gambit list is the player deciding ONCE and then watching. The two can coexist -
      FF XII lets you override any turn - but they pull against each other, and the standing rule
      is that *decisions* are the point of a fight, not its length
      ([[feedback_length_is_not_the_goal]]). A gambit system that is good enough removes the
      decision it was built to serve.

      **Where it clearly EARNS its place, and this is the strongest argument for it:**
      * **The companion**, which already acts on its own with no player input at all - a tactics
        list is pure gain there, because there is no decision being replaced.
      * **Party members' absent characters**, if party play ever allows a member to be AI-run.
      * **Trivial fights**, which the auto-resolve already skips - a tactics list is the same
        instinct applied to fights that are nearly trivial.

      **⛑ So the cheap first slice is the COMPANION, not the player.** It tests the whole idea -
      UI for building rules, the evaluator, whether players enjoy authoring them - against a
      combatant whose turn is currently invisible and unchosen. If it is fun there, widening it to
      the player is a scope decision made with evidence instead of a guess. **Ask the owner before
      building the player-facing half.**

      Open questions, none answered: how many rules, are slots earned or free, does a card's
      resource cost gate a rule, what happens when no rule matches (attack? skip?), and does a
      gambit-run turn still animate at full speed or fast-forward.

- [ ] **Dungeon card pass — re-scoped 2026-09-17: the COVERAGE half is done, the POWER half is
      not.**
      <!-- audited: 2026-09-19 --> Verified still open: all 53 cards exist and are themed (the
      coverage half), and nothing has measured whether substituting one for a class's weakest deck
      slot raises or lowers its win rate. That is the POWER half and it is untouched. This is also
      the LIVE entry for the duplicate in the balance batch. Owner: *"dungeon reward cards likely need reworked and added to add interesting new
      cards that classes may want to swap into their decks."*
      **Done:** *"added"*. All 53 dungeon types have an exclusive card, each themed to its own
      boss and sized to its own tier, each with a face — see the 53-card entry in the dungeon arc.
      Several DO rattle the enemy, which this entry asked for: 3 blind, 3 stun, 4 weaken, 3 charm
      and 3 timestop.
      **Still open, and it is the harder half:** *"cards that classes may want to swap into their
      decks"*. The bar is **a card a player would CHOOSE over one of their five**, and nothing has
      measured whether any of the 53 clears it. That is a sim question, not a writing one — the
      shape of it is: for each class, does substituting a dungeon card for its weakest deck slot
      raise the win rate or lower it? Until that is run, "53 cards exist and all 53 work" is the
      honest claim and the only one the probe makes.
      → **Moved to THE BALANCE BATCH 2026-09-18**: it is a sim run, and what it produces is card
      buffs, which are per-class power changes. Both halves belong in one batch window.

## Phase 5 — the dungeon arc (the big content direction)





- [~] **DUNGEONS GET A RARITY — AXIS 1 WAS ALREADY SHIPPED; AXIS 2 IS NOT WHAT THIS ENTRY SAYS
      IT IS.** Owner 2026-09-11: *"Dungeons should have a rarity moving forward."* Checked on
      2026-09-18 before building, per the standing rule, and both halves came back differently
      than the entry described.

      **✅ AXIS 1 (type rarity) IS DONE AND LIVE.** This entry claimed `spawn_weight` *"is read by
      nothing in the codebase"* and that selection was uniform. Not true any more:
      `DungeonDatabase.pick_weighted_type()` reads it, and BOTH live spawn paths call it
      (`server.gd:32260` and `:32270` via `_pick_weighted_dungeon_type`). There is also a
      `pick_weighted_type_for_grade()` that additionally weights toward species suited to the
      country, used by the quest-dungeon path at `:32500`. No uniform picker survives anywhere -
      the only remaining mention of `randi() % dungeon_types.size()` is inside a docstring
      describing what it replaced. **Fourth shipped-but-unticked item found this way; see
      [[feedback_verify_before_building]].**

      **✅ AXIS 2 (grade rarity) — DONE 2026-09-18, after an owner decision.** It could not be
      done as the entry described it, because there was no roll to weight: a dungeon's grade was
      **deterministic** from the land, so within one country every dungeon was the same grade and a
      rank 9 there was not rare, it was impossible. The real question was whether to INTRODUCE
      variance. Owner: *"I'm fine with some variance and rare finds, it would help keep those finds
      interesting and diversify the Quests offered on the board BUT, it shouldn't be huge jumps
      like we had before where it goes up entire grades (like a G2 where an H2 normally is)."*

      Chosen from measured options: **1-3 ranks above the land, clamped inside the same letter,
      about one dungeon in twelve.** One rank is ~3% power and nine ranks is a whole grade, so the
      cap is ~+9% - a real find that is never a trap. `PowerRank.varied_grade()`, applied at both
      world spawn paths and at the quest board.

      **⛑ HASHED FROM THE DUNGEON'S IDENTITY, NEVER `randi()`**, and that is the whole safety
      argument. A grade is computed independently by the overworld marker, the quest board, the
      accept path, the entry warning and the turn-in; a roll at any of them re-creates v0.9.802's
      bug, which the owner met as *"Board showed H2, where it points me shows G2."* The key is the
      world POSITION for a spawned dungeon and the QUEST ID for a board quest - both stable for the
      life of the thing they identify, so every surface computes the same answer with no storage.

      **⛑ AND THE PROBE CAUGHT A REAL DEFECT THAT THE AGGREGATE HID.** The first version took
      `hash(key) % 12` directly. Across a broad sweep that measured **7.4% raised against an 8.3%
      target - correct** - and it was badly broken for the keys this actually receives: 300
      dungeons along one line (`wd:0,0`, `wd:13,0`, `wd:26,0` ...) every one came back with the
      **identical** grade, because Godot's string hash carries structure in its low bits and
      structured keys are all this is ever given. The rate after the fix is *also* 7.4% - the
      aggregate could never have found it. Only asking "do two dungeons in the same country ever
      differ" did (1 distinct rank before, 4 after). The hash is avalanched before any modulus now.
      `tools/probe/rare_dungeon_grade.gd`.









- [ ] **Dungeon revamp — the design IS captured** <!-- audited: 2026-09-19 --> Verified 2026-09-19: **workstream A is now COMPLETE** (theme roll/look, themed egg, and the
      pre-entry warning, which turned out to be already built). E shipped. D has its first five
      telegraphs. What remains is B (waits on the card POWER half), F (waits on the party system)
      and the questing replacement. Original: , in `docs/design/dungeon_revamp.md` (139 lines)
      plus `docs/design/dungeon_themes.md`. This line used to say "details not yet captured",
      which was stale and undersold how much has already shipped: instancing + no re-farm,
      bigger dungeons, wandering-monster pressure replacing the step budget, branching paths,
      four special room types, Azure-Dreams floor loot, and dungeons as the main egg source.
      Six workstreams; what is LEFT, and what each waits on:
        * **D bosses** (phases / telegraphs / adds, telegraph counterplay mandatory) — nothing
          blocks it.
        * **E presentation** (zoom, sprites, void instead of wall tiles, wider room spacing)
          — **DONE, shipped v0.9.760-767.** See the ticked entry above.
        * **A slice 2 — A MODIFIED DUNGEON NOW LOOKS LIKE ONE. DONE 2026-09-19.** Every monster in
          a dungeon that rolled modifiers shares one colour and pattern, DERIVED from those
          modifiers so it cannot drift from the mechanics. One modifier reads solid, two a
          gradient, three (rank 9, the worst built) striped — so how loaded a place is is legible
          without counting. Purely cosmetic: the probe asserts the stamp writes `appearance_*`
          only, because the modifier stats are already applied through `modifier_effects()` and
          doubling a difficulty modifier under permadeath surfaces in a death log, not in testing.
          Proven to fire by injecting a `max_hp` write. Probe:
          `a_modified_dungeon_looks_it.gd`.
          ⚡ **A parallel THEME system was written and reverted first** — `dungeon_themes.md`
          predates `DUNGEON_MODIFIERS` by three weeks and reads as though nothing exists. See the
          doc's new "the mechanical half already exists" section.
        * **A slice 3 — the boss egg / companion inherits the dungeon's look. DONE 2026-09-19.**
          Passed through `get_egg_for_monster`'s existing `pre_rolled_variant` hook, so the
          companion that hatches inherits it too. **No `rarity` key on purpose** - that field
          scales HATCH TIME, and inventing one would turn a cosmetic feature into a change in how
          long eggs take. Probe: `the_egg_matches_its_dungeon.gd`.
        * **QUEST BOARDS OFFER THEM. DONE 2026-09-19** (owner: *"we want to ensure Quests can be
          offered for these dungeons... so players can choose to take them on the Quest boards."*)
          Quest dungeons already rolled modifiers; the board never said so. A quest is described
          BEFORE its dungeon exists - offered, possibly regenerated from its id, instance created
          on accept - so the roll is now SEEDED on the quest id and all three moments agree.
          Note `Array.shuffle()` uses the GLOBAL RNG and would have defeated the seed; the seeded
          roller walks the pool itself. Probe: `the_board_does_not_lie.gd`.
        * **✅ THE CHAIN IS PROVEN JOINED, not just link by link.** Owner set the bar: *"It doesn't
          need to read as ominous it just needs to show as it was advertised and work as
          intended."* `advertised_is_what_you_get.gd` walks ONE quest id through the REAL server
          path - board promise → instance → `_stamp_dungeon_look` → a spawned monster - and
          asserts 25 monsters share one look, no stat moved, and a plain dungeon is untouched.
          Worth having because three correct links wired to different sources is exactly the
          `refcal` two-worlds bug found the same day.
        * **A slice 4 — show the modifier BEFORE entry. ALREADY BUILT** (verified 2026-09-19, not
          assumed). The dungeon-entry warning already prints *"This place is not ordinary"* with
          an **Unusual** row per modifier - name, colour, cost and payoff - then *"Harder, and it
          pays for it."* It reads them off the instance the player is about to enter and is
          explicit that it never re-rolls. Owner's bar: *"as long as it is advertised in the info
          a player sees before entering a dungeon, that is all we need."* Met.
          ⚑ My earlier note that "only one passing reference to modifiers exists in the client"
          was wrong - I had grepped for the wrong word. **WORKSTREAM A IS COMPLETE.**
        * **(historical) A 2-4** — ⚠ **was BLOCKED, and
          this line said "nothing blocks it" until 2026-09-19, which was wrong.**
          `docs/design/dungeon_themes.md` carries an explicit owner gate from 2026-08-25:
          *"there are more things we need to discuss regarding dungeons before you go off building
          a bunch of things. This is supposed to be a dungeon revamp so it will require planning
          and discussion."* → **"After shipping slices 0+1, DO NOT proceed to slice 2 or beyond.
          Open a broader dungeon-revamp planning discussion first."**
          **Slices 0 and 1 ARE shipped** (verified 2026-09-19, not assumed):
          `monster_database.reapply_variant` exists at :1878 with eight callers (it was a live
          crash when the doc was written), and monsters carry `appearance_color` / `color2` /
          `pattern` since v0.9.718. So the authorised work is done and the rest is waiting on a
          CONVERSATION, not on code.
          **What the discussion owes an answer to**, from the doc: structure, floors, pacing,
          bosses, rewards, entry/warning UX, and what "revamp" means beyond themes. Also settle
          the naming collision the doc flags - the modifier is "Catalyst", which already names
          something in the fusion system ("Ascension Catalyst").
        * **B loot/discovery** (signature drops, Dungeon Atlas) — waits on the dungeon card pass,
          and the Atlas has grown into the realm meta-loop (Phase 6).
        * **F party in dungeons** (the declared north star, most architectural) — waits on the
          party system itself, which has unfixed bugs (Phase 4).
      **Balance rule REVISED 2026-09-08:** dungeons may be PARTY-UPGRADABLE — much harder, much
      riskier, much better rewards — provided a solo option always exists and is completable.
      Not "one dungeon, more bodies"; an opt-in difficulty tier, signposted before entry.


## Phase 6 — realm meta and sinks

- [ ] **Real sinks for excess eggs and companions**: shops, breeders, trainers, fusers, companion <!-- audited: 2026-09-19 --> Verified: every mechanism it names EXISTS - 4 fusion modes, breeder NPCs, the egg market, the kennel. What is missing is not machinery but a reason to use it, so this is a DESIGN item, not a build one.
      tasks. Much is already scaffolded (fusion, breeder NPCs, egg market, kennel).
- [ ] **⚑ THE WORLD CONSUMES MATERIAL SURPLUS AND MAKES GEAR OF IT — owner direction 2026-09-18.**
      <!-- audited: 2026-09-19 --> Verified still open: no market-surplus conversion exists
      anywhere in server/ or shared/ (the `surplus` hits are the unrelated `transmute` sink).
      Its own text trips a DONE-word scan by saying the surrounding steps already exist.
      *"If the materials build up on the market to the point where we have a large surplus they
      could then be consumed to make gear appropriate to that area that is then market listed and
      transported around like the merchants already do. That would help with the living world arc
      as well."*

      **⛑ THIS CLOSES A LOOP RATHER THAN ADDING A SOURCE, which is why it is worth more than any
      of the three problems it touches.** Players gather → list the surplus → the world consumes it
      → gear appropriate to THAT AREA appears on the market → couriers carry it around. Every step
      already exists except the conversion.

      What it answers, in three arcs at once:
      * **Crafting fault 1** - *"materials have no destination"*. A surplus that nobody wants is
        precisely the pile the player is staring at, and this gives it somewhere to go **without
        requiring the player to do anything**.
      * **Merchant stock** - the honest fix for empty couriers. Their goods come from PLAYER
        material, not from a generator, which is the owner's *"most of the economy should come
        from the players"* satisfied rather than worked around.
      * **Living world** - the world visibly produces, not just spawns. Supply appears where the
        material came from, so a region's output tells you what is gathered there.

      **Design questions, none settled:**
      * What counts as *surplus*? A per-material threshold on total market quantity, presumably
        per REGION rather than globally, or the gear would not be area-appropriate.
      * How fast does it convert, and does it drain enough to actually relieve the pile?
      * Who is the seller, and where does the valor go? If the conversion pays nobody, it is a
        pure sink; if it pays the listers, it is a price floor for materials, which is a much
        bigger economic lever and needs thinking about.
      * Does it compete with PLAYER crafters? It should undercut nobody - the whole point of the
        crafting arc is making player crafting worth doing. **Likely answer: it converts only the
        surplus ABOVE a threshold**, so it is a relief valve, never the main supply.

      **Sequencing:** wants the **valor economy pass** first (it mints or moves valor), and it
      pairs with **living world**. The interim consumables floor shipped for road merchants on
      2026-09-18 is deliberately small and does NOT sell gear, so it does not conflict with this -
      but if this lands, revisit whether the floor is still needed at all.


- [ ] **Living world / rework the posts. ⛑ SEQUENCE IT AFTER PLAYER PHANTOMS** <!-- audited: 2026-09-19 --> Genuinely open; the audit flags it only because this entry's own text says the PARTY code "shipped", which is about a different item. (assessment
      2026-09-19, owner asked what I thought of the two). It is a BUNDLE rather than one feature -
      companions around posts, NPCs, wandering travellers, recruitable party members, threats woven
      in - and its own scope note says it is downstream ("it is what those populate") and that it
      **overlaps the phantom prefab tiers**. Built first, it produces a post-population model that
      the phantom prefab then has to redo. Also: "recruitable party members" would land on the
      party code shipped 2026-09-19, which no two players have exercised yet.
      Designed 2026-09-04 as **step 4 of the companion
      spine**, and the detail is in `docs/archive/BACKLOG_journal_to_2026-09-07.md` (item 16) —
      not undesigned, just archived. Scope: companions living around the posts, **NPCs, wandering
      travellers and recruitable party members**, and threats woven into the posts rather than
      sitting beside them. It follows the companion drops and the egg/companion sinks because it
      is what those populate. **Overlaps the player-phantom prefab tiers** (a bought post's quest
      boards and workstations are the player-owned half of the same idea) — design the two
      together or the post will have two unrelated populations.

## Phase 7 — endgame: THE UNBURIED (deliberately later)

Owner 2026-09-07: not needed for a long while. It is the mechanism that makes the top of the ladder
reachable, so it pairs with revisiting the high-level win targets — but nothing depends on it yet.

An aspirational milestone admits a player to **The Unburied**: great powers that affect the realm
and other players, plus **3 extra lives**, and possibly a further life from a hard endgame loop
(deliberately not easy, so members are not effectively unkillable).

The name is exact against the setting bible: a phantom is a dead thing the ground refuses to keep
down, and these are the ones it keeps sending back — which is what extra lives ARE.

## Phase 8 — later / unscheduled

- [ ] **Prize Shuffle** loot-minigame redesign (combat done; gathering and crafting remain). <!-- audited: 2026-09-19 --> Verified still open: the combat half IS built (`combat_loot_panel.gd` has the preview, shuffle
      and hunt phases); gathering and crafting still use the plain scratch-off.
## ⚑ RESTORED FROM THE ARCHIVE 2026-09-18 — four items that were dropped, not finished

Owner, after the player-phantoms design turned up archived rather than listed: *"were there other
things we discussed around then that could have been archived instead of properly added to the
backlog?"* Audited `docs/archive/BACKLOG_journal_to_2026-09-07.md` against this file. **Four were
lost.** (The other two archives are genuinely complete: `QUEST_AND_DUNGEON_REDESIGN.md` says ALL
PHASES COMPLETE, and `ROADMAP.md`'s "future considerations" are shipped or trivial.)

⛑ The tell on the second one below is that **this backlog already REFERENCES the Unburied** - the
high-level win-target item says *"revisit alongside the Unburied"* - while the item defining it was
nowhere in the file. A reference to something that is not here is the cheapest possible signal that
something was dropped, and it sat unnoticed for eleven days.


- [ ] **THE UNBURIED — the permadeath counterweight. Owner direction 2026-09-07, named by the
      owner, never started.** An aspirational milestone admits a player to the Unburied:
      **great powers that affect the realm and other players** (the first genuinely social endgame
      hook in the design), **3 extra lives**, and possibly a late endgame loop granting one more for
      a hard-won achievement - deliberately not easy, so members do not become unkillable.
      **This is the mechanism that breaks the compounding maths at the top of the ladder**, and it
      is why *"most characters die"* and *"a careful player reaches the top"* are not in conflict.
      Supersedes the vaguer `project_permadeath_may_change` note.
      The name is exact against the setting bible: a phantom is a dead thing the ground refuses to
      keep down, and these are the ones it keeps sending back - which is what extra lives ARE.

- [~] **NINE CLASSES, THREE CARD POOLS — RE-VERIFIED 2026-09-18, and the archived version is
      HALF STALE.** Owner, on the restoration: *"Each class now has its own starter deck and
      playstyle so that may be stale info."* Correct, and checked rather than assumed by re-running
      the archive's own two tests against current code:

      | layer | keyed to | state |
      |---|---|---|
      | starter deck | **class** — `CURATED_STARTER_DECKS_BY_CLASS` holds all **9 of 9**, each with its own written reasoning | ✅ differentiated |
      | engine shape | **class** — one shape each since 2026-09-07 | ✅ differentiated |
      | learnable pool | **archetype** — `get_all_available_abilities()` still does `match get_class_path()` and appends one of three fixed lists | ⚠ converges |

      The archive also cited `grep -c 'class_type ==' shared/character.gd` returning **0**; it
      returns **2** today. So the headline claim - *"the nine classes are three classes with three
      stat-curve variants each"* - is **no longer true** and should not be quoted.

      **What actually survives is narrower and arrives LATER:** a Sage and a Sorcerer start with
      different decks and run different engines, and then both can learn the same nine mage cards.
      Identity is strongest at creation and erodes as a player rebuilds their deck toward whatever
      is best. Two things soften even that, and neither existed when the archive was written: the
      **53 dungeon cards** (one exclusive per dungeon type) and **companion cards**, both
      cross-class pools a player can differentiate with.

      **✅ ANSWERED BY THE OWNER 2026-09-18: diverge.** *"Archetype-wide is what we are trying to get
      away from. We've done that well with the current class engine of each and card naming/slight
      differences."* So this stays open as real work, and the Paths revamp inherits the same answer
      - class-specific, not archetype-specific.

      **⛑ AND THE MECHANISM ALREADY EXISTS, which changes the cost enormously.**
      `ABILITY_DISPLAY_BY_CLASS` in `combat_manager.gd` maps card id → class → name, and it already
      covers **18 of the 27 archetype cards with 28 class-specific renames** (a Ninja
      *Hamstrings* where a Grifter *Sabotages*; a Wizard drops a *Meteor*, a Sorcerer a
      *Cataclysm*, a Sage an *Unmaking*). So the naming layer is roughly two thirds done.

      **The proposed ladder, cheapest first — NOT three separate pools:**
      1. **Finish the naming layer.** 9 cards still read identically across their archetype. Pure
         fiction work, zero balance risk, and it is the thing a player notices first.
      2. **Per-class numeric variation on shared cards.** The owner's *"slight differences"*. A
         Barbarian's Cleave and a Fighter's should not be the same numbers. Carries balance risk,
         so it belongs to a **BALANCE BATCH** window.
      3. **One or two EXCLUSIVE cards per class**, not a separate nine. Nine to eighteen new cards
         rather than a rewrite, and it keeps the shared spine that makes an archetype legible at
         all - a Sage and a Sorcerer should still both read as mages.

      ⛑ **Three fully separate pools is the expensive version and probably the wrong one**: it is
      ~18 new cards to author and balance, the payoff lands only on players deep enough to have
      rebuilt their decks, and it risks dissolving the archetype as a readable idea. Recommending
      1 → 3 → 2 in that order, with 2 deferred to a batch.


- [→] **⚑ CRAFTING STATION SPRITES — THE CHECKABLE HALF IS RESOLVED; THE REST NEEDS AN EYEBALL.**
      Owner's suspicion was specific: *"many of them were multiblock sprites that got ripped into
      1."* Measured 2026-09-19 against `bake_overworld_tiles.py`: **all six are baked at their
      authored span** - forge 3x2, workbench / enchant_table / banner / writing_desk 2x2,
      brazier 1x2. **None is cropped to a single tile.** So the fragment fault the item names is
      gone (the multi-tile work fixed it; the release gate counts 20 such tiles).
      What remains is whether they read CLEARLY at map scale, which no grep can answer -
      marked as owner-action rather than unstarted work. Original direction 2026-09-18:
      *"All of the crafting stations sprites likely need to be reviewed individually. I think many
      of them were multiblock sprites that got ripped into 1 and they don't seem very clear or
      memorable on the map."*

      The suspicion is specific and checkable: a sprite authored as part of a MULTI-TILE building
      and then cropped to a single tile shows a fragment - half a roof, a corner of a wall - which
      reads as noise at map scale. That is a different fault from "the art is poor", and it has a
      different fix: either restore the multi-tile footprint (the overworld already supports
      multi-cell tiles - the release gate counts **19 of them**) or choose a single-tile sprite
      that is legible on its own.

      **A station has to be recognisable at a glance from across the map**, because that is the
      entire job it does there - the player is looking for the anvil, not admiring it.

      **Measure first:** list every station, the sprite each one resolves to, and whether that
      sprite is a crop of a larger source. Capture them at real map scale side by side - a sprite
      that is unclear in a file browser may be fine in place, and vice versa, and this codebase has
      a standing rule that art questions are settled by looking rather than by reading paths.



- [ ] **Sanctuary redesign — put the house in the world.** Owner direction 2026-09-01, written
      up as item 15 in `docs/archive/BACKLOG_journal_to_2026-09-07.md`. **Read it before
      building.** Today the Sanctuary is a menu between login and character select
      (`HOUSE_SCREEN`); the owner wants a real place — near the starting post is the suggested
      anchor — so that going home is travel, not a screen. Plus **customisation** (personal, not
      a fixed room) and **more to do with companions there**, coordinated with the egg/companion
      sinks rather than inventing a parallel set. Keep what works: account-level persistence
      through permadeath, the kennel (30-500 slots), the Fusion Station.

      **The one decision that must come first**, because it drives chunk cost, griefing and what
      happens when thousands of accounts each own ground: a shared world district, an instanced
      interior behind a world doorway, or true claimed land. Prior art exists either way — player
      posts already claim real tiles (`add_player_tile` / `get_player_tiles` / enclosure checks),
      so the sparse-tile storage pattern is proven.
- [~] **PLAYER PHANTOMS — the outward loop. STARTED 2026-09-19, HELD BEHIND A FLAG.**

      ⚑ **`PHANTOM_POSTS_ENABLED := false` in server.gd. Nothing below reaches a player until it
      is flipped.** Owner: *"implement in a way where if we don't finish we can hold anything
      breaking."* The flag is checked at BOTH doors - the listing and the purchase - because a
      client can send any message it likes, so guarding only the build menu leaves the till open.
      Probe: `a_held_feature_is_really_held.gd`, proven to fire by removing the purchase check.

      ✅ **SLICE 1 BUILT (held): the Valor charter ladder.**

          Waystation Charter   12,000 valor    7x7    market
          Outpost Charter      30,000 valor    9x9    market, quest board, workbench
          Bastion Charter      75,000 valor   11x11   market, quest board, workbench, forge, storage

      Bought from the build menu as an ITEM, placed later by the existing kit path - so the
      charter sits in the pack until the player is standing where they want it, which is the point
      of pushing out to place one, and a bad spot costs a walk rather than the Valor.
      Layouts are GENERATED (`shared/prefab_posts.gd`), not hand-listed: the existing crafted kit
      spells out all sixteen tiles of its 5x5, which becomes a transcription exercise at 11x11 and
      a wall with one tile missing is a post monsters walk into. The probe derives the expected
      perimeter count and checks every rung.

      ⚡ **PRICED AGAINST MEASURED HOLDINGS, and the gap in that is named.** Live valor across 13
      accounts, 2026-09-19: `68294 63835 47194 24550 1396 338 163 99 29` and **four at zero**. A
      hard split - four established accounts, everyone else under 1.5K. So Waystation is reachable
      today by four players and Bastion by none. **What this does NOT know is the valor EARN rate**
      (a stock, not a flow), so it says who could buy today and nothing about how long saving
      takes. Measure that before calling the prices final.

      ⛑ **NO TIER MENTIONS A PHANTOM, DELIBERATELY.** The Phantom is the whole point of these
      posts and it does not exist yet; Valor is not refundable by any path in the game, so a
      charter promising one is a debt that cannot be settled. Each rung is priced to be worth it
      for the POST alone, and the Phantom joins the layouts when it works. The probe fails if any
      tier's name, blurb or station list mentions it.

      ✅ **THE FOUR GATING DECISIONS — ANSWERED BY THE OWNER 2026-09-19.** These were the open
      questions the 2026-09-02 design listed and could not settle. They are settled now:

      1. **DIFFICULTY: the Phantom gets its OWN BAND, scaled by investment.** Its floors scale
         with what was fed to it, so reward and danger rise together and
         `reference_monster_curve.json` is left completely alone. This is the only shape where
         *"the farther out, the better"* can keep escalating without making every future balance
         measurement unreadable — an uncapped reward inside the shared curve would invalidate it
         continuously and by a different amount per player.
         ⛑ **So a Phantom's levels are NOT the overworld's.** Anything reading a phantom monster's
         level as an overworld level (XP formulas, threat, post anchoring) has to be checked.
      2. **THE PUMP IS GATED BY DEPTH AND SURVIVAL RISK — and by nothing else.** Better output
         comes only from deeper floors, and deeper is genuinely more dangerous. The owner chose
         this ALONE, rejecting diminishing returns, a lossy exchange and a cooldown: you pay for
         an upgrade in risk, which is the one currency that cannot be farmed safely. ⚡ That puts
         the whole weight on depth danger being real — if deep floors are survivable by a
         well-geared player without meaningful risk, the pump is open and nothing else is holding
         it.
      3. **EGGS: a GUARANTEED egg deep in, plus quality on top.** A deterministic floor — reach a
         certain depth and an egg is certain — with quality as the variable part. Effort always
         pays something, so a bad run is a smaller reward rather than the "reads as theft" case
         the design warned about.
      4. **OWNERSHIP: the ACCOUNT owns the post and everything fed into it; what you are carrying
         OUT is still lost on death.** A death does not erase weeks of investment, but "what you
         brought out alive" stays intact — which is what lets the loop pay forward onto new
         characters, the thing the design says is the point.

      ✅ **SLICE 2a BUILT (held): the MODEL, in `shared/phantom_model.gd`.** Pure functions over a
      post's investment record - no server state, no generation - so the whole thing is measurable
      before a single tile exists. It encodes the four decisions:

          max_depth_for(distance)      4 floors at the origin -> 20 at radius 2200
          floor_level(...)             OWN band. Never consults the calibrated curve.
          investment_weight(...)       SATURATING: 100x the investment is worth 1.49x
          species_weights(...)         the ground remembers, never forgets (no species -> 0)
          guaranteed_egg_depth(...)    always 70%+ down
          egg_quality_bonus(...)       depth CUBED x investment
          gear_bonus(...)              depth squared x companions

      ⚡ **EVERY REWARD IS DEPTH-FIRST, INVESTMENT-SECOND, AND THAT IS FORCED BY DECISION 2.**
      Because depth-risk is the ONLY pump guard, volume must buy nothing depth does not also
      demand - so the investment term is MULTIPLIED by a steep depth term rather than added to it.
      Measured: an absurd hoard (400 eggs, 100 companions) buys **0.002** on floor 2 and **1.905**
      on floor 20. Farming the safe floors pays nothing.
      Probe: `the_phantom_pump_is_shut.gd`, proven to fire by removing the depth term.

      ⛑ **THE PROBE CAUGHT A REAL FLAW IN MY OWN MODEL** and it is the recurring shape: my comment
      said *"investment stretches the CEILING, never the floor"* while the code lerped from
      `depth / max_depth`, putting floor ONE five percent up the ramp. A stocked Phantom was
      already harder the moment you stepped in - so the only way to learn what you were in would
      have been to be told beforehand, when the whole design is that you find out by descending.
      Fixed to `(depth - 1) / (max_depth - 1)`.

      ✅ **SLICE 2b BUILT (held): the investment record and the feed surface.**
        * **Persisted on the POST record**, which is keyed by username - and username maps
          one-to-one with account, so decision 4 (the account owns it) is what this file already
          stored. No migration, no second keying. `get_post_investment` normalises on the way OUT
          so every caller sees one shape whatever an older record holds.
        * **Written IN PLACE**, not by rebuilding the post record - a post carries a name, a
          centre, a creation time and a clan id, and rebuilding it to add one field is how one of
          those quietly goes missing. The clan-share function beside it carries the same note.
        * **Fed while STANDING IN THE POST**, never from a menu anywhere in the world. The loop is
          push out, found a place, stock it; doing it remotely removes the journey, which is the
          part the feature exists to create.
        * Eggs and companions are **consumed permanently**, so the confirmation names exactly what
          went in - there is no way to check afterwards and no way to undo it.
        * Your ACTIVE companion cannot be fed, the same guard the release path uses.

      ✅ **AND THE AUDIT DECISION 1 IMPLIES IS ARMED EARLY** -
      `a_phantom_level_is_not_an_overworld_level.gd`. A phantom level and an overworld level are
      both an integer called `level` and mean different things; CLAUDE.md records **six
      player-facing leaks and two reward-formula leaks** from exactly that shape (`base_tier` is
      not `tier`). Today nothing spawns from a phantom level, so it passes trivially - it is armed
      so the FIRST wiring into generation fails with the checklist in hand: XP payout, threat
      escalation, post anchoring, the death log's level-gap column, and quest "kill a level N"
      targets.

      ✅ **THE FIVE-SURFACE AUDIT IS DONE — and it made the feature SAFER than the decision
      implied.** Carried out 2026-09-19 BEFORE any generation was written, which is the whole
      reason it changed the design instead of producing a bug list.

      **The finding: "its own band" should mean its own choice of LEVELS, not a parallel stat
      curve.** `generate_monster_by_name(name, level)` derives stats from `compute_anchored_stats`
      AND xp from `_calculate_experience_reward`, both from that level - so a monster generated at
      level 73 IS a level-73 monster in every respect. A Phantom is therefore dangerous by
      fielding HIGHER-LEVEL monsters than the country outside would, not by inventing creatures
      the curve has never seen. Consequences, all checked:

          XP payout          correct - it really is a level-73 kill
          threat / hotzones  never sees it; those are functions of world POSITION
          post anchoring     same - get_post_anchored_level(x, y) is positional
          death-log gap      correct - the player really did die 43 levels above themselves
          quest "kill a N"   correct

      ⚡ **SO THE RISK IS NOT ON THE MONSTER SIDE AT ALL.** It is on the REWARD side: eggs and gear
      *"beyond the normal tier/sub-tier ceiling"* are player power outside anything the curve
      knows. That is the thing to watch, and it is still unbuilt.

      ✅ **SLICE 2c BUILT (held): generation, as an OVERRIDE inside the existing spawner.**
      `_spawn_dungeon_floor_monsters` takes its level from `PhantomModel.floor_level` and its
      species from `_phantom_species_pick` when the instance carries a `phantom` block. **Not a
      forked spawner** - one code path for phantom and ordinary floors, so they cannot drift.
      Species weighting is competitive rather than exclusive: the unfed pool keeps a fixed share of
      every roll, so a themed phantom still surprises.
      Probe: `a_phantom_level_is_not_an_overworld_level.gd`, re-pointed from the countdown it used
      to be ("nothing generates yet") to the rule that actually keeps it safe - phantom floors must
      spawn through `generate_monster_by_name`, and the spawner must never assign hp/strength/
      defense itself. Proven to fire on that exact shortcut.

      ✅ **SLICE 2d BUILT (held): the reward side — the half the audit named as the real risk.**
        * **The guaranteed egg** is placed by DEPTH, at `guaranteed_egg_depth` (70% down). Gated on
          the floor number and never on investment: stocking a post cannot make a shallow egg
          certain, because that would be the laundering pump with its only brake removed.
        * **Egg quality** climbs with depth cubed x investment. Measured: a well-stocked Phantom
          pays 0.004 at floor 3 and 1.333 at floor 20 — **296x**, so the bottom is where the value
          is and a safe descent is worth nothing.
        * **Gear** climbs with depth squared x companions consumed, the gearing axis from the design.

      ✅ **ANSWERED 2026-09-19 — PROVENANCE, NOT RANK.** Owner, rejecting all three options I put
      up: *"Eggs/companions that hatch out of them should have an additional multiplier or
      something that makes them unique and stronger than a duplicate you would find out in a normal
      dungeon, ie an e4 in a dungeon is not as strong as an e4 from a phantom."*

      ⚡ **AND I HAD THE NUMBERS WRONG WHEN I ASKED.** I said egg rank was *"worth up to 2x its
      stats"*. Measured:

          rank 1 -> rank 9 WITHIN a tier      1.26x
          tier H -> tier S                    8.16x
          one full GRADE step                 1.30x
          rank 10, 12, 15                     IDENTICAL to rank 9 - `power_index` already
                                              does `clampi(rank, 1, RANKS)`

      So the clamp I had been carefully defending was holding back **nothing**, and the decision I
      was about to ask for was the wrong decision. Rank is a dead axis; tier collides with the
      grade ladder and every surface that reads a letter.

      **So provenance rides ALONGSIDE the grade.** `phantom_power` is stamped on the egg when it is
      rolled (the only moment the provenance is certainly knowable - the Phantom may be demolished
      or re-stocked before the companion is next loaded), inherited at hatch, and applied through
      `DropTables.companion_stat_mult`. **Capped at 1.35x** = about **1.14 grade steps**, sized
      against the ladder so it is a real prize and not a tenth grade.
      ⛑ `companion_variant_mult` was the "use this everywhere" chokepoint until provenance became
      a second axis; all four live sites in `character.gd` moved to the new total, because a site
      left behind would make a companion stronger in combat and ordinary on its own card.
      Probe: `a_phantom_born_companion_is_stronger.gd` - it walks the whole journey (egg → hatch →
      companion → multiplier) because dropping it at ONE step leaves everything working and the
      feature silently absent. Proven to fire by deleting the hatch line.

      ✅ **SLICE 2e BUILT (held): the descent, and the prize made visible.**
        * `handle_enter_phantom` builds an ordinary dungeon instance carrying a `phantom` block.
          **There is no second dungeon system** - every generator reads that block and falls back
          to ordinary behaviour without it, so a Phantom and a Goblin Caves share one code path.
        * Depth is `max_depth_for(distance)` and the floors BUILT are the same number, via a new
          `floor_override`. If those two ever disagree the bottom floor is not the bottom of the
          reward curve and the best rewards are unreachable - the probe asserts they match.
        * The instance is **rebuilt every descent**, not persisted: the investment lives on the
          post, the floors are disposable. So a player cannot clear half a Phantom, re-stock it
          and return to old floors with new rewards.
        * **Theming is derived from `monster_pool`**, taking the LOWEST-tier home of the
          most-fed species - so a goblin-fed Phantom reads as goblin caves rather than as whatever
          late-game place also fields goblins.
        * **The provenance is now VISIBLE** - `(Phantom-born +N%)` on the companion display. An
          unseeable prize is a wasted one: without it a player fights to the bottom of their own
          Phantom, carries an egg out alive, and gets a companion that looks identical to any other.
        Probe: `you_can_descend_into_your_own_phantom.gd`, proven to fire by dropping
        `floor_override` - the failure it guards is *"it works, but it is an ordinary dungeon"*,
        which looks completely fine from inside.

      ⚡ **AND THE GATE CAUGHT ME INVENTING A FUNCTION AGAIN**: `DungeonDatabase.dungeon_type_for_species()`
      does not exist. `tools/gdcheck.sh` refused the commit. The mapping is now derived from the
      real `monster_pool` data instead, which cannot go stale the way a hand-kept helper would.

      ▶ **WHAT IS LEFT — THE CLIENT, AND THEN THE FLAG.** Every server handler exists
      (`list_prefab_posts`, `buy_prefab_post`, `feed_phantom`, `enter_phantom`) and **nothing calls
      any of them**. That is the whole remaining task: a build-menu surface to list and buy
      charters, a feed UI, and a Descend action inside a post. When those work end to end, flip
      `PHANTOM_POSTS_ENABLED`.

      ▶ **SLICE 2 — THE PHANTOM ITSELF. Remaining open questions** (from the archive, still open):
        * valid placement area (min distance from existing posts, terrain rules)
        * whether a Phantom is per-post / per-account / shared, and who else may enter
        * reward gating: enough to gear a fresh character locally, without becoming the best farm
          in the game for an established one

      ⚠ **WHAT REMAINS TO MAKE SLICE 1 ITSELF SHIPPABLE** (i.e. to flip the flag): a build-menu
      surface on the CLIENT to list and buy the charters. The server side is done - `list_prefab_posts`
      and `buy_prefab_post` - and nothing on the client calls them yet. That is the next hour of
      work, not a design question.

      Original item follows.

- [ ] **PLAYER PHANTOMS — the outward loop.** <!-- audited: 2026-09-19 --> Verified still open: nothing in server/ or shared/ implements it (the `phantom` hits are the
      setting bible's wording and the Ninja's Phantom Strike card). The whole design already existed and this list had
      lost it. Owner 2026-09-17, asked for the scope: *"Player phantoms(aka dungeons) are buildable
      inside of a player owned trading post... players can purchase a semi-randomized buildable
      player post from the build menu and place it on a valid placement spot. It will cost a
      substantial amount of valor to buy. The cheapest will only have a market and a phantom
      surrounded by walls with one door and enough room to move around inside. More expensive ones
      will be larger and have more player structures like quest boards, workstations, etc. There
      should be something on the to do about this if not you need to go back and find our
      conversation where we spoke about player posts."*

      **⛑ THE DESIGN WAS NOT MISSING — IT WAS ARCHIVED.** It is item **12b, "The Phantom — the
      outward loop"**, written up in full on 2026-09-02 (hook, egg economy, companion economy,
      prefab posts, theming, nine open questions, and a measurement that corrected one of my own
      claims). When this list was rewritten on 2026-09-07 the whole section went to
      `docs/archive/BACKLOG_journal_to_2026-09-07.md` (≈line 5701) and what survived here was the
      two words `Player phantoms.` That is how a fully-specified feature came to be re-asked as an
      open question. **Read the archive section before building; do not re-derive it.** The same
      trap is live for `Sanctuary redesign.`, `Living world / rework the posts.` and
      `Minigame variety.` — check the archive for each before treating any of them as undesigned.

      **The loop (verbatim from the owner, 2026-09-02):** push out into the wilderness as far as
      you can survive → found a post there and stock it with eggs and companions you no longer
      need (consumed, permanently) → descend into that post's Phantom to win better gear and
      companions → push further out and repeat. **The farther out, the deeper the Phantom can go
      and the better what is inside it**, given the investment. This is the outward pull the
      difficulty model cannot supply: encounter level is a pure function of position, so the
      pressure has to come from the reward gradient — and here the player builds that gradient
      themselves, at the edge of what they can survive.

      **Eggs set what the place remembers.** Each egg is consumed, makes that monster type more
      likely to spawn on the Phantom's floors, and **buffs the eggs of that type found inside**
      beyond the normal tier/sub-tier ceiling — a goblin egg pulled from a heavily-invested player
      Phantom is far stronger than an identical-tier one from an overworld dungeon. Eggs inside are
      **at least 10x rarer**: the thing a player hunts long and hard for, where getting it *out
      alive* is the payoff. This is what turns surplus eggs from clutter into something carried
      forward onto new characters.

      **Companions are the gearing axis.** Companions you no longer want are consumed to make the
      **equipment** found in the Phantom stronger — the gear a fresh character needs to survive
      the wilderness outside. A dignified use for retired companions and a second sink for the
      same oversupply.

      **Theming, already drafted against the setting bible.** The ground under a new post is
      already remembering something. **Feeding it eggs teaches it which shapes to wear** — give it
      goblins and it comes back up goblin. **Giving it companions**, things that lived alongside
      you, is why it returns *possessions*: gear is what the place kept of them. The 10x egg rarity
      is the fiction too — a place only rarely produces something still living, and you have to
      carry it out past everything else it remembers.

      **What the owner ADDED on 2026-09-17, which sharpens the prefab half:** the post is bought
      from the **build menu** as a semi-randomised prefab and placed on a valid spot, for a
      substantial Valor cost. **Cheapest tier = a market and a phantom, walled, one door, enough
      room to move around inside.** Dearer tiers are larger and add player structures — quest
      boards, workstations. So the prefab is a **tier ladder priced in Valor**, not one item: that
      is the shape to build, and Valor's only current sinks are bounties, PvP payouts and repairs,
      so size it against those.

      ⚡ **THE RISK NOBODY HAS WRITTEN DOWN, and it should be settled BEFORE any code.** This
      design deliberately creates a power source **outside the calibrated curve**: phantom eggs are
      buffed *"beyond the normal tier/sub-tier ceiling"* and consumed companions make the gear
      inside stronger. CLAUDE.md's standing rule is that anything changing player power invalidates
      `reference_monster_curve.json` - and an investment ladder with no ceiling invalidates it
      continuously, by a different amount per player. Two honest shapes, and the choice is the
      owner's:
        * **A CEILING.** Investment moves you UP the existing tiers faster and further, but tops
          out somewhere the curve already knows about. Keeps one difficulty model.
        * **ITS OWN BAND.** A phantom's floors scale with what was fed to it, so the reward and
          the danger rise together and the overworld curve is left alone. More work, and it is the
          version that actually matches the fiction.
      Deciding this late means finding it in a death log, which is the most expensive place.

      **Prerequisite, and it is now met.** 12b was blocked on companion power — a level-1 companion
      was statistically identical to no companion, so a hard-won 10x-rare egg would have hatched
      into something that changed nothing. That was fixed 2026-09-13 (grade ladder monotonic,
      ascension/fusion carrying the best input level). **The reward no longer rings hollow, so this
      is unblocked.**

      **Open questions to settle before code** (carried from 12b, still open):
      * Does investment raise the egg **RATE** or only egg **QUALITY**? 10x rarity plus pure RNG
        means a dry run reads as theft after a heavy investment. Prefer a **deterministic floor**
        (a guaranteed egg at certain depths) with quality as the variable part.
      * **Account vs character ownership.** Permadeath means the character who built and stocked
        the post can die. The post and its investment must survive at the **account** level, but
        what is carried *out* of a run must still be lost on death.
      * **Guard the laundering pump** — invest cheap eggs, extract better eggs, hatch, invest those
        companions, get better gear, repeat. The exchange must be lossy and gated by **depth and
        survival risk**, never by volume.
      * **The Phantom needs its OWN scaling model.** Measured 2026-09-02: low-tier monsters hit a
        hard HP **cap** when scaled up (Goblin and Wolf both land on exactly 15,000 HP at L5000),
        so seeding cheap low-tier eggs would produce monsters that stop getting harder with depth
        while the player keeps levelling. Depth must set difficulty for **any** seeded species, so
        anchor to depth (and through it to a reference player), never to each monster's
        hand-authored `base_level`.
      * **Valid placement** — minimum distance from existing posts, terrain rules.
      * Is a Phantom per-post, per-account or shared, and who else may enter?
      * **Check whether the player-post suppression-floor change is still parked.** 12b recorded a
        *"DO NOT DEPLOY before 12b exists"* on it, because spawn-at-post already ships and the
        change stranded a level-1 character at a frontier post. That note is not in this list any
        more — find out whether it shipped, was dropped, or is still sitting in the tree.

      **Do not confuse this with the OTHER thing called player phantoms** — dead characters
      persisting as things in the world, raised under the roguelike-progression item. They share
      vocabulary deliberately; only this one is specified.
- [→] **Minigame variety — SAME WORK AS THE PRIZE SHUFFLE LINE, from a different angle.** Its own
      text says so ("fold them when either is started"), so it is not a second task. Kept as a
      pointer. Item 17 in `docs/archive/BACKLOG_journal_to_2026-09-07.md`, and it
      is concrete: **port the Chain / Mystery / Trap mechanics from combat loot to gathering and
      crafting** (the combat slice shipped as v0.9.644-645), plus **trap chests, a Mimic chest
      variant, and the 2 remaining dungeon-exclusive consumables**. It is the same list as the
      Prize Shuffle line above from a different angle — fold them when either is started.

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


---

## ⚑ LAST ON THE LIST — the death curve runs the wrong way (measured 2026-09-13)

**Scheduled deliberately last, at the owner's direction.** It is documented here rather than
acted on, because acting on it means a per-class balance pass plus the full calibration chain,
and there are live players.

### What was measured

Two independent READ-ONLY audits, both against ordinary same-level monsters - not over-level
gambles, not elites. `run_fight(level, gear, "normal", ...)`.

`riskcurve` - death per encounter, 216 fights a cell, all nine classes:

    level      gearless      under    average        bis
    3             14.8%       0.0%       3.7%       0.0%
    10            37.0%      14.8%       7.4%       0.0%
    30            88.9%       7.4%       0.0%       0.0%
    100           96.3%      18.5%      11.1%       3.7%
    500          100.0%      29.6%      22.2%      11.1%

`endgame` - best-in-slot survival, 450 fights a level (50 per class):

    level     won   retreated    DIED   survived
    100       49%        46%     5.3%      94.7%   below the 95% target
    250       30%        60%     9.6%      90.4%   below
    500       38%        54%     8.0%      92.0%   below
    1000      48%        47%     5.1%      94.9%   below

### What it means

1. **Risk RISES with progression instead of falling.** A best-in-slot player goes 0% at L30 to
   3.7% at L100 to 11.1% at L500. `project_what_balanced_means` says the opposite: *death risk
   must FALL with progression*.
2. **A well-geared endgame player dies about one fight in ten.** Under permadeath that ends
   characters who did everything right, which is the one outcome the pillar rules out.
3. **Gear does pay** - 100% to 11.1% at L500 - so the careful player's route up exists. It just
   does not reach far enough.

### What it is NOT

Not sampling noise: n=216 a cell for riskcurve (±5.5pp at p=0.22) and n=450 a level for endgame,
and the trend is monotonic across five levels and two separate harnesses.

Not the retreat model hiding losses: `endgame` counts survival as *won OR retreated in time*, so
these are deaths after every escape has been allowed for.

### What fixing it costs, and the trap

`CLAUDE.md`: **a global player buff cannot fix a per-class gap** - the chain holds win rate at
target, so any across-the-board buff is cancelled by monsters getting stronger on the next refit.
Only PER-CLASS changes survive. And **the chain optimises WIN rate and is blind to DEATH rate**,
so a refit can hit its win target while this column climbs.

So the order is: `forensics` (read-only) to find WHICH classes and WHAT is killing them, then a
per-class change, then `speciescal` -> `refcal` -> `rolecal` once each (~25 min), then re-run
`riskcurve` and `endgame` to confirm the column moved. Treat every balance number measured
between the change and the re-calibration as stale.

Related: [[project_what_balanced_means]], [[feedback_orthogonal_calibration]].
