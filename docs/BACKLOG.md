# Phantom Badlands — Master Backlog

**The single ordered to-do list.** Read it before proposing what to work on; update it as work
lands. Items are ordered so each one's inputs are settled before it starts — working out of order
is what forces revisits.

History lives in `docs/archive/BACKLOG_journal_to_2026-09-07.md`. Search it before re-opening
anything: it records why several approaches were REJECTED, and re-proposing those is the most
common way to lose a session.

---

## ⚑ OWNER DIRECTION 2026-09-13 — the world reshape and what it exposed

All of this came out of the distribution work. Recorded before starting any of it.

### BLOCKING the release

- [x] **DONE 2026-09-13, shipped in v0.9.780.** ONE-TIME TELEPORT to the starter post. Owner: *"we should probably have
      everyone teleported back to the starter post on their next login just this once. So they
      can navigate out again."* The reshape moves the country under standing characters - someone
      at radius 700 was in ~L400 country and is not any more. Must ship WITH the reshape, must
      fire exactly once per character, and must be obvious to the player why it happened.
- [x] **ANSWERED 2026-09-13.** From the ORIGIN, yes and substantially: L50 country moved from
      radius 150 to 480, L100 from 234 to 900. From the NEAREST POST, barely: suitable ground is
      within 10 tiles of *some* post for L10/L25/L50/L100, because posts anchor the level to
      their own country. The design therefore leans entirely on players being able to FIND the
      right post - which is why post distribution is the next item and not a separate one.
      Was: **Does a player now have to travel much farther...** Owner asked directly. It is a real consequence of widening the early bands - L100 used to be at
      radius 250 and is now at 900. MEASURE it (distance to reach level N, before vs after) and
      report honestly before shipping; if the walk is unreasonable the curve is wrong.
- [x] **DONE 2026-09-13** - verified in a live client/server: relocation landed the test
      character at (0,-2) Crossroads, the area readout renders, the stance bar renders.

### NEXT, in the order the owner raised them

- [x] **DONE 2026-09-13 — WATER: small lakes and rivers, rare large lakes.** Owner: *"I'd like
      water to be more of small lakes and rivers with rare large lakes, instead of just big
      bodies of water."* It was ONE noise layer at 0.03 over a 0.62 threshold - a recipe for
      blobs, with no way to express a river at all. Three layers now (small lakes roughened by a
      second octave, drifting rivers, rare great lakes) and deep water follows the depth field
      instead of a per-tile hash that speckled impassable pixels through shallow crossings.
      Measured in a 400x400 window: 11.4% water, 127 bodies, 118 small, 5 large, one river
      running the full 399 tiles.
      **The numbers passed a version that was wrong.** The first rivers used `abs(noise-0.5)`,
      whose contours are CLOSED LOOPS - it scored "127 bodies, mostly small" while drawing a
      honeycomb of canals that would have cut the map into compartments. Only the render showed
      it. The fix is a drift term that dominates the noise so contours stay open.


- [x] **DONE 2026-09-13 — TRAVEL STANCES.** Four, from one shared table both sides read:
      Travelling (encounters x0.18, recovery x0.35), Wary (today's behaviour, the baseline),
      Scouting (x0.75 encounters, x0.7 recovery, +2 map sight), Hunting (x2.2 encounters, x0.85
      recovery). Buttons generated from `TravelStance.ORDER` so the bar cannot disagree with the
      server. The probe asserts NO stance is strictly better than Wary - and caught that Hunting
      originally cost nothing, which made it a free switch rather than a choice.
      Was: **TRAVEL STANCES (owner direction 2026-09-13) — the main answer to the longer walk.**
      Owner: *"I was debating having different stances or something where you can toggle between
      like an evasive stance where you don't get as much back each step or from rests but you're
      much less likely to hit random encounters, we would need a couple more like this and it
      would have to be an obvious toggle likely just under their over world map with multiple
      different colored selections, and explanation for the player."*

      **Why this is newly viable:** the regen penalty only became a real cost in v0.9.779, when
      resource costs doubled and the bar started binding. Before that, "less back each step" was
      a penalty nobody would feel. The two changes make each other work.

      Proposed set — four, one per intent, colour-coded under the map with a one-line
      explanation each:
      * **Travelling** (evasive) — encounters far rarer; regen per step and from rests cut hard.
        You cross ground and arrive tired.
      * **Wary** (default) — today's behaviour, the baseline everything else is judged against.
      * **Hunting** — encounters much more common, better rewards. Should ABSORB the existing
        Hunt action rather than sit beside it, or there are two ways to do one thing.
      * **Scouting** — wider vision, spots gatherable clusters and dungeon markers further out;
        normal encounters, higher upkeep.

      **What already exists and must not be duplicated:** roads already halve the encounter rate
      (`check_encounter`), and there is level-diff scaling at -5% per level above the area,
      FLOORED AT 10%. That floor is the real complaint - at +18 levels a player still rolls
      encounters at a tenth of base, which over a 500-tile walk is many interruptions.

- [x] **TRIVIAL-ENCOUNTER AUTO-RESOLVE — BUILT 2026-09-16, unreleased.** When the ground is far
      below you the fight resolves where you stand: one line, and the FULL reward, exactly as the
      owner accepted it.

      **It does not compute a payout.** `CombatManager.resolve_without_fight` starts the real
      fight and wins it on round zero, so XP, job XP, companion XP and battle count, gems, path
      effects, card gifts, quest credit and the bestiary all come from the code a real victory
      runs — by construction, not by being kept in step. A third reward site is precisely how the
      co-op payout paid raw base XP for months.

      Trivial means: monster level at or under your level / 3, you are level 12+, and the fight is
      not an EVENT — no elite, no boss, no rare variant, no threat-corridor spill, no hunting
      ground, nothing summoned by a Selection Scroll.

      `tools/probe/trivial_encounter.gd` verifies the payout against `kill_xp` passed through the
      character's own `add_experience`, and **found three real faults doing it**: the fight was
      left registered and the character left `in_combat` (a stuck character nothing on screen
      would have shown); ELITE was tested with a `role` key that does not exist on a generated
      monster; and the probe's own first expectation was wrong, because `kill_xp` is the
      pre-multiplier sum and `add_experience` applies race + Sanctuary on top.

      - [x] **TESTED IN PLAY 2026-09-16, and the live test found three things the probe could
            not.** (1) The threshold was a RATIO in dead ground: `check_encounter` has zeroed the
            encounter rate at +20 levels since v0.9.620, and "level / 3" only met that at +20 or
            worse, so it could never fire while walking - the only path reaching it was HUNT,
            which bypasses the scaling, i.e. the one fight the player had asked for. Now a level
            GAP of 10, inside the live band, and a hunted fight is never resolved. (2) The line
            printed **"+808080 XP"** - the reward scraped out of its own `[color=#808080]` tag.
            The resolve reports what it banked now. (3) Common rare variants were excluded as
            "events", so some rats resolved and some opened a screen, which reads as broken;
            only elites and bosses are events.
            Confirmed working by the owner across goblins, zombies and a giant rat, with
            level 9 enemies still fighting at the smaller gap.

- [ ] **POST-TO-POST ROAD TRAVEL — ACCEPTED by the owner 2026-09-13** (held as a separate
      decision, and answered separately).
      Standing on a road at a discovered post, offer travel to another discovered post along it,
      fast-forwarded with a chance of interruption. It is the most direct answer to "travel is
      long" and it is also the one that could most easily devalue exploration, which is why it
      should be decided on its own rather than bundled.
      **Owner's acceptance set the price: it costs TIME AND RESOURCES, not nothing.** That is what
      keeps it from devaluing the walk - arriving with a drained bar is a different arrival than
      teleporting in fresh.

- [x] **DONE 2026-09-13 — Roads: three tiles wide, and ten times quieter.** Measured: 6.7
      encounters per 200 steps on the road against 67.2 beside it. Deliberately NOT zero - a
      perfectly safe road turns every journey into a rail and makes the wilderness beside it
      pointless. The widening needed the per-tile skip rules pulled out of the stamp loop, or a
      band would pave post interiors, bridges and (newly guarded) water at its edges.
      Was: **Roads: wider, and encounters very rare on them.** Owner: *"make paths/roads generate a
      little wider and make encounters very rare on them so players can traverse and explore the
      map without running into a crazy amount of encounters."* Directly mitigates the longer
      travel above - the two are the same problem seen twice.
- [x] **DONE 2026-09-13 — Post distribution.** The problem was not sparsity, it was CLUSTERING:
      `POST_PLACEMENT_RADIUS` was 600 in a world of radius 2828, so all 60 posts sat in the inner
      5% of the map by area and every one stood in H-D country. Median distance from a random
      spot to a post was 1,353 tiles and 87% of the world was over 400 from one.
      Now 120 posts out to radius 2600 (count derived from area, not taste): median 321, 37.5%
      beyond 400, and posts in every grade including 28 in S country. Tier bands extended to the
      world edge so the outer world is not one undifferentiated tier.
      **Cost verified flat** at the owner's prompting: 7.05ms a step at 60 posts, 7.04 at 120,
      7.42 at 240 - the bucket index made post count a design choice rather than a budget.
      Was: **Post distribution — are there enough to navigate BY?** Owner: *"ensure we have a
      sufficient number of posts for people to navigate to while exploring."* 60 posts over a
      4000x4000 world is one per ~267,000 tiles. Measure mean distance from a random point to the
      nearest post before deciding a number.
- [x] **HOTZONES serve no purpose - revamp or replace.** Owner: *"hotzones don't serve much of a  **DONE v0.9.783 - rich hunting grounds that relocate every 3 hours.**
      purpose anymore. I've been thinking we either need to revamp or replace them."* Needs a
      design conversation, not a patch. What were they for, what does regional menace now do
      instead, and what is the gap that remains?
- [x] **DONE 2026-09-13 — GATHERABLES come in patches.** Every tile used to roll independently at
      25-35%, so a third of the world was nodes, uniformly smeared, no two related. A coarse
      field now marks patches, each patch commits to ONE resource (type keyed to a grid twice the
      width of the blobs, or a stand straddles cells and comes out a mixed hedge), and the
      density between patches is a tenth of what it was. Coverage 30% -> 6.1%; 2,903 of 5,504
      nodes stand in groups of 12+; 45 of 80 large stands are a single resource.
      **NOTE FOR BALANCE:** gatherable coverage fell ~5x. Yield per tile WALKED drops accordingly
      - which is the intent (destinations, not terrain) but it is a real economy change and the
      gathering jobs have not been re-checked against it.
      Was: **GATHERABLES should be CLUSTERS, not scatter.** Owner: *"I don't really like the
      distribution... I feel like they should be clusters you run into sort of like the hot ones
      are, where you run into a large group of trees or a bunch of mining spots altogether.
      Having them scattered everywhere makes them obstacles more than actual activities players
      engage with."* That last sentence is the whole brief: scattered nodes are terrain, clustered
      nodes are a destination.
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

## ⚑ WHERE THE LIST STANDS — recounted 2026-09-18 after v0.9.803 (the combat log arc closed)

Counted mechanically (`- [ ]` vs `- [x]` across this file), not estimated. **The working order is
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

- [x] **RANK 9 FROM DUNGEONS, BUT RARE.** A rank-9 clear can hand back a rank-9 boss egg only on  **DONE 2026-09-13** - `_boss_egg_rank`: below rank 9 the egg is exactly the dungeon's rank; at rank 9 it is rank 8 with a 15% roll for 9. Measured 15.3% over 4000. Guarded by `tools/probe/floor_egg_rank.gd`.
      a low roll; otherwise it caps at 8. Both routes to the top rank stay alive and fusion is not
      obsoleted. *(Replaces the "decide" item below.)*

- [x] **DUNGEON RARITY = ALL THREE AXES.** — **COMPLETE, and LIVE in v0.9.798.** All three axes
      were built on 2026-09-13 and sat unreleased; axis two's entry-screen surface was finished on
      2026-09-16 (the modifiers state their cost and reward in numbers, and the screen they appear
      on was rebuilt to be readable). This was "the biggest single item left in the arc".
      The owner picked better loot quality **and** rolled
      modifiers **and** rarer monsters / a guaranteed unique. So a rarer dungeon pays more, reads
      differently before you enter it, and holds different things. This is the biggest single item
      left in the arc; build it in that order - loot scaling first (it rides existing code),
      modifiers second (the new surface), monsters/unique third.

      **✅ AXIS ONE (loot quality) BUILT 2026-09-13, unreleased.** `_dungeon_loot_rarity_upgrade`
      on the server feeds the `rarity_upgrade` ladder bump that already existed for the Plunder
      card, wired into every live dungeon equipment source (final chest x2, floor loot x2).
      Rank 1 never upgrades; rank 9 upgrades 40% of drops, a quarter of those by two steps.
      Measured, not guessed - `tools/probe/dungeon_rank_loot.gd`:
        * tier 1: rare-or-better 10% -> 23%
        * tier 5: rare-or-better 23% -> 53%
        * tier 9: epic 89% -> 54%, legendary 8% -> 37%, artifact 3% -> 10%
        * the drop RATE is unchanged - rank buys quality, not quantity
      **The first cut was too strong and measuring is what caught it.** At 0.55 it put
      legendary-or-better at 59% of tier-9 rank-9 drops, making legendary the ordinary outcome.
      Tiers 8-9 already floor every drop at epic (`TIER_MIN_RARITY`), so the same knob bites far
      harder at the top than the bottom. `RANK_LOOT_UPGRADE_MAX` / `RANK_LOOT_DOUBLE_SHARE` are
      the dials if the owner wants it moved.
      **✅ AXIS TWO (rolled modifiers) BUILT 2026-09-13, unreleased.** `DUNGEON_MODIFIERS` in
      `shared/dungeon_database.gd` - six ARPG map affixes, each of which makes the place harder
      AND pays for it in the same line, so it reads as a trade rather than a punishment.
      Rolled ONCE at `_register_dungeon`, the documented single chokepoint, rather than in the
      four instance literals - that is exactly the condition the rank-9 egg drifted under.
      `modifier_effects()` is the one place they are folded into numbers; every consumer asks it.
      Measured (`tools/probe/dungeon_modifiers.gd`, 30 checks):
        * rank 1-2 always plain (you have to see an ordinary dungeon before a modified one means
          anything); rank 9 averages 2.1 modifiers, and 2.7% of rank-9 dungeons still roll none
        * compounded worst case over every 3-modifier combination: HP x1.77, damage x1.38,
          armour x1.35, floor population x1.40 - and the least-paying triple still pays 1.51
        * shown on the ENTRY WARNING before you commit, which under permadeath is the whole cost
          of the feature
      **✅ Known gap CLOSED 2026-09-16.** The probe proved `modifier_lines` and the effects but
      never executed `handle_dungeon_enter`, so the warning CALL SITE was unverified - the same
      shape that let the v0.9.774 figure fix ship twice under a dead branch. There was no headless
      route to that screen (every GM entry pre-confirms; the player route needs a `D` tile in
      walking distance), so `gm_enter_dungeon` gained `warn` / `modified` and the shots harness
      gained a `dungeonwarn` scene. Captured on a real modified instance: the rows render, off
      live rolled modifiers, with the numbers the table holds.

      **✅ And the modifiers now state the TRADE in numbers.** `modifier_lines` gave the name and
      the flavour blurb - "What died here did not finish dying" - and never once said 40% more HP
      or +20% XP, which is not something a player can weigh. `modifier_rows()` DERIVES the wording
      from the same fields `modifier_effects` folds, so a tuning change moves the screen with it;
      `modifier_lines` is built from it, so the dungeon list cannot drift from the entry screen.
      Probe: `tools/probe/dungeon_modifier_rows.gd` (31 checks, all PASS).

      **✅ AXIS THREE (rarer monsters / guaranteed unique) BUILT 2026-09-13, unreleased.**
      `DUNGEON_BOSS_UNIQUE_CHANCE` - a table, not a curve, so any single step can be retuned
      without solving for an exponent. 2.5% at rank 1 climbing to 40% at rank 8 and **100% at
      rank 9**; the jump is the point, it is the reward the owner chose for the rarest grade.
      `DUNGEON_RANK_EMPOWER_CHANCE` is the "rarer monsters" half: 0% at rank 1-2 rising to 45% at
      rank 9. The two compound on purpose - every Empowered modifier is +0.75% on the unique roll,
      so a rarer place holds rarer monsters that are themselves likelier to pay.
      Probe: `tools/probe/dungeon_rank_uniques.gd`.

      **⛑ It also closed a hole that was already open and that party dungeon combat would have
      widened: CO-OP ROLLED NO UNIQUES AT ALL.** Not reduced - absent. `_end_party_combat_all`
      never checked. Every party fight in the world had this, so "bring a friend" was the way to
      guarantee you never saw the rarest reward in the game, and shipping party dungeon combat the
      same day would have made that the normal way to play. `_unique_drop_chance` is now one
      definition both paths call, rolled per member so the named item stays a personal moment.
      Verified by driving the real `_end_party_combat_all`, not by reading the call site.

      **The whole three-axis item is now DONE, but NONE of it is playtested,** and two call sites
      are proven only by their helpers: the entry-warning display (axis two) and the dungeon
      completion/teleport path around the co-op unique roll. Live checks owed.

- [ ] **⚑ PARTY PLAY FOLLOWS THE DRAGON QUEST IX MODEL — owner direction 2026-09-18.**
      *"For party play we should probably go in the style of Dragon Quest IX: Sentinels of the
      starry skies... when a party member nearby enters combat it will pull nearby party members
      into the combat as well (we will have to figure out the best way to handle this as players
      may both be moving around at the same time and could possibly enter 2 separate combats very
      close to the same time). Party Players could also join mid-battle as they could visually tell
      on the map if a player was in battle and they could run into them to enter it."*

      **What this decides.** Half two was already "independent movement + join-in-progress"; this
      names the MODEL, which settles the open question of how a party that walks around separately
      ever fights together. Two mechanisms, and the second is the fallback for the first:

      * **PROXIMITY PULL.** A party member entering combat drags nearby members in with them.
      * **RUN-IN JOIN.** A member who was not pulled can see on the map that a teammate is
        fighting and walk into them to join. This is also what makes the pull radius forgiving:
        being out of range is not an exclusion, it is a short walk.

      **⛑ THE RACE THE OWNER NAMED IS THE REAL DESIGN PROBLEM, and it is not an edge case.** Two
      members moving at once can each trigger an encounter within the same tick, so "pull nearby
      members in" is ambiguous by construction - each fight tries to claim the other's owner.
      Options, cheapest first:
        1. **One combat per party, ever.** The party holds a single combat slot; whoever claims it
           first wins and the second trigger JOINS that fight instead of starting one. Simplest,
           and it cannot produce a split party. Cost: the second monster is either discarded or
           added to the first fight.
        2. **Claim with a tie-break.** Both start, and a deterministic rule (lower peer id, or the
           earlier server-stamped tick) folds the loser's encounter into the winner's.
        3. **Let both exist and let members choose.** Most faithful to two people genuinely far
           apart; most work, and it needs the map to show WHICH fight is which.
      Whichever is chosen, **the decision belongs to the server on one clock** - the bug this
      shape produces is two clients each believing they started the fight, which is exactly the
      class `_combat_ui_busy` was introduced to kill.

      **⛑ CHECK WHAT ALREADY EXISTS FIRST.** Party combat is BUILT - shared monster debuffs,
      per-member rewards, the flatten-log-per-recipient path, `_PARTY_SHARED_MONSTER_KEYS`. The
      new work is the ENTRY into it, not the fight. Read the existing half-one notes below before
      designing.

      **Prerequisite:** independent movement. Today party members move as one; the pull and the
      run-in join are both meaningless until they can be apart.

- [ ] **PARTY PLAY — HALF TWO (the mechanics underneath the model above): independent movement + join-in-progress combat.** (Half one, dungeon
      party combat, is built and live; the onboarding guide it blocked has shipped.) Original title:
      PARTY PLAY IN DUNGEONS + JOIN-IN-PROGRESS COMBAT.
      This is what *"party play isn't working properly"* (2026-08-26, never reproduced) actually
      meant. Owner 2026-09-13: *"likely regarding no support for it in dungeons and possibly
      making it where players can navigate themselves but then join each other when they are in
      battle (would need a visual indicator on the map to show a party member is in battle and a
      way to handle a party member joining the combat etc)."* It was filed as a bug for a year;
      it is two pieces of design. Re-filed as such.

      **Half one - dungeon party COMBAT is missing. (Corrected 2026-09-13 - see below; the
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

- [x] **SHIPPED v0.9.788-v0.9.791 as Warden's Watch.** ~~ONBOARDING: a tutorial + a starter chain that reaches level 1. ⚑ DEPENDENCY of the
      questing replacement - build this FIRST.~~ Owner 2026-09-13: *"There should be a tutorial or
      early game dungeon quest in our to do list that will help alleviate your concerns."*

      **It was not in this list.** The design exists and has since 2026-05-17, but only in the
      memory file `project_tutorial_starter_quests.md` - it had never been written into the repo
      backlog, which is the precise way work gets lost between arcs that this file exists to stop.
      Recorded now.

      What that memo already settles, and is still right:
        * a zero-gear character is led through a SAFE loop that ends with one starter item in each
          empty slot - earned through the first few steps, not handed over at creation
        * it stays inside the starter post's bubble geometry, which already exists, so no
          threat-corridor monsters and no apex spawns can reach it
        * gear matches the class (weapon -> armour -> trinket cadence, tier 1)
        * skippable but obvious, so a returning player can walk past it

      What the 2026-09-13 decision CHANGES about it: the memo describes a GATHERING chain, and
      questing is now dungeon-centred. The starter chain should end in a dungeon a level-1
      character can actually clear - which is also the thing that stops "replace the overworld
      quests" leaving an empty first hour. Scope the two together.

      **✓ MEASURED 2026-09-13, before building anything - and it moved the design.**
      The open question was whether a level-1 gearless character can clear a starter dungeon at
      all. `-- newplayer`, 60 fights a cell, against what actually spawns:

      | level | gearless | +kit | +kit/unc | +kit/comp | reference |
      |---|---|---|---|---|---|
      | 1 | **76%** | 83% | 96% | 90% | 91% |
      | 3 | 71% | 88% | 93% | 90% | 95% |
      | 5 | 53% | 85% | 90% | 86% | 80% |
      | 10 | **16%** | 76% | 86% | 80% | 71% |

      **Per FIGHT, a naked level-1 is fine** - 76% against a 60% design target. The starter
      dungeon does not need to be made soft. Three other things decide whether it is survivable,
      and none of them is the fight:
        1. **ATTRITION, which is the real killer.** In a dungeon you recover **0.5% of max HP per
           step**, half the overworld rate. A tier-1 dungeon is 3 floors and the per-floor count
           scales with floor AREA up to **14** - so a bad roll is ~40 fights at 76% each with
           almost no healing between them. The starter dungeon has to be a BESPOKE SMALL
           instance (1-2 floors, a handful of monsters), not a stock tier-1 roll.
        2. **A new character cannot rest.** `handle_dungeon_rest` consumes a food material and
           `handle_create_character` grants NO inventory at all - a character created today walks
           in with nothing. The chain must hand over food before the dungeon, or the one recovery
           mechanic in the building is locked.
        3. **Gearless falls off a cliff by L5-L10** (53%, then 16%). The chain has to produce real
           gear inside the L1-L3 window, which is exactly what the 2026-05-17 memo already said -
           now with a number attached to why.

      **✅ THE TWO STRUCTURAL BLOCKERS ARE FIXED 2026-09-13, unreleased.**
        * **The starter dungeon is now SHORT.** A `starter` flag is set on the origin dungeon by
          `_ensure_starter_dungeon_exists`, inherited into the personal instance on entry (the
          marker on the map is not what you fight in), and caps the run to
          `STARTER_DUNGEON_FLOORS` 2 and `STARTER_DUNGEON_MONSTERS_PER_FLOOR` 4 - about nine
          fights including the boss. **A stock one is FIVE floors of up to fourteen, so up to 70
          fights.** Note five, not the three the table says: `get_dungeon` size-scales what it
          serves, so reading `DUNGEON_TYPES` directly gives the wrong number.
        * **A created character now carries 3 Healing Herb** (`STARTER_RATIONS`). The in-dungeon
          Rest button consumes a food material and `handle_create_character` granted no inventory
          at all, so the one recovery mechanic in the building was inert for precisely the players
          who need it.
      Probe: `tools/probe/starter_dungeon_size.gd`. **Still owed: a live run.** Per-fight win rate
      is measured at 76%, but whether a gearless level-1 survives nine fights on one health bar
      is a playtest, not a calculation.

      **⛑ OWNER DECISIONS 2026-09-13 (asked before building, answered in one batch):**
        1. **The guide holds AGGRO.** Owner: *"Guide should have all aggro to ensure player
           survives unless its a hit that the player can for sure survive."* This replaces the
           question I asked, which was about HP scaling, with a better mechanism: survival is
           guaranteed by TARGETING, not by softening the monster. The player still takes hits -
           the ones they can certainly live through - so they learn combat is real while never
           being killed by the tutorial. **My reading, stated so it can be corrected:** the guide
           is therefore excluded from the party HP multiplier as well, because a 2x-HP boss that
           the guide is tanking is only a longer walkover, not a better lesson.
        2. **The guide LEAVES for good** when the dungeon is cleared. One-off content; no
           persistence, no NPC-ally system, no balance implications past L3.
        3. **Structure: a controlled first fight, then the dungeon** - owner: *"with a bit of
           option 2"*, so the guide keeps teaching INSIDE the dungeon rather than falling silent
           at the door. Floor one is still part of the lesson.
        4. **The tutorial grants the companion egg**; creation no longer does. The egg becomes a
           reward rather than a handout, and a player who skips the tutorial gets one from the
           first dungeon they clear.

      **⛑ AND IT HAS TO FILL A SLOT THAT IS CURRENTLY ADVERTISED AND EMPTY.** The welcome
      overlay every new character sees still names *"Pathfinder's Trial - a starter quest in your
      log that rewards gear as you complete it."* The GRANT was retired 2026-09-03 in favour of
      this very item, so the first thing a new player reads points at an empty quest log. The
      definitions still exist (so anyone mid-chain can finish) but nothing offers it.

      **✅ THE ESCORT IS BUILT 2026-09-14, unreleased.** `Warden Hollis` (`GUIDE_NAME`,
      `GUIDE_PEER_ID` -9001) joins a LONE player in the starter dungeon as a real party member:
        * listed in `npc_members`, so it does not scale the monster
        * holds aggro on any hit the player might not survive, and lets through the ones they
          certainly will (`CombatManager._guide_shield_targets`)
        * acts for itself each round via `_guide_fill_action`, on both the command and the
          item-use submit paths - the second was needed or spending your turn on an item would
          stall the round forever waiting for a member with no client
        * appears only in the STARTER dungeon and only when the player has no party
      Probes: `guide_aggro.gd`, plus section 6 of `dungeon_party_combat.gd`.
      **✅ THE CHAIN IS BUILT 2026-09-14, unreleased — `Warden's Watch`, three stages.**
      Granted at creation (the slot Pathfinder's Trial left empty on 2026-09-03), named by the
      welcome overlay, and it arms in the order the measurement demands: weapon, then armour, then
      trinket, all inside the L1-L3 window before the gearless curve turns at L5. Stage three is a
      DUNGEON_CLEAR that the guide escorts, and it pays the companion egg — creation no longer
      hands one out, so the egg reads as earned. Probe: `tools/probe/starter_chain.gd`, 33 checks,
      including that the overlay names something that is actually granted.
      **✅ THE TEACHING LAYER IS BUILT 2026-09-14, unreleased.** Owner chose panel-then-voice.
      One `tutorial_hint` panel per system - items, equipment, combat - fired the first time that
      system MATTERS rather than all at once at the gate, plus `_guide_say` for the guide's own
      voice as each reward lands. Three flags on the character, serialised, so a reconnect does
      not replay the tutorial. Probe: `tools/probe/guide_teaching.gd`.
      **ONBOARDING IS NOW FEATURE-COMPLETE AND ENTIRELY UNPLAYED.** Everything left on it is a
      playtest: whether nine fights on one health bar is survivable gearless, whether three stages
      land before the L5 cliff, and whether the writing works. The guide's turn AI is
      deliberately a plain attack - its job is tanking, and something clever would make the
      tutorial about watching.

      **A GUIDE NPC carries the new player through it, as a party member.** Owner 2026-09-13:
      *"an NPC should help introduce the player to mechanics, Items, equipment, combat etc. and
      help carry the charaacter through the dungeon using the party combat."* So the guide is not
      a wall of text at a signpost - it teaches by standing next to you, and it fights in the
      starter dungeon on the EXISTING co-op machinery, which means a first dungeon is survivable
      because someone competent is in it with you, not because the monsters were made limp.

      Checked against the live code before writing this down, because it decides the size.
      (Corrected: the LIVE entry point is `start_party_combat_simul`, the simultaneous #64 model.
      The turn-based `start_party_combat` and its server wrapper `_start_party_combat_encounter`
      are the superseded path and `_start_party_combat_encounter` has NO callers - dead code.
      The structural finding below was re-checked against the simul function and holds.)
        * `start_party_combat_simul(members, characters, monster)` is handed its OWN character map
          and stores it as `combat.characters`; every resolution site reads that, never the
          server's global `characters`. So the guide can exist as a `Character` INSIDE one fight,
          under a synthetic (negative) peer id, and never enter the global registry - which is
          what keeps it out of the 31 sites that iterate `characters` (chat broadcast, the
          who-is-online feed, geo events, the map figure payload, persistence).
        * `send_to_peer` returns immediately for an unknown peer, so every broadcast-to-members
          loop is already safe against a member with no socket.
        * `submit_party_action(leader, pid, action)` is pure state - no networking, no client ack.
          The server can act for the guide. `_dev_autoact_fill` already does exactly this for
          every non-leader member; it is dev-gated (`--autoact`), so the production path is new
          but the mechanism is proven.
        * `_party_award_drop` and `_party_collect_fallen` both open with `if not characters.has(pid)`,
          so the guide silently takes no loot and cannot permadie. That is the behaviour we want
          and it is already there.
      So this rides existing machinery. The REAL work is: turn AI for the guide (which card, when),
      the teaching script itself, the client showing a non-player member, and **sizing** - party
      combat multiplies monster HP by member count, so adding the guide doubles the boss's HP. A
      starter dungeon tuned for one must be re-tuned for two, or the guide makes the fight longer
      rather than safer.

      **⚑ HARD BLOCKER, found 2026-09-13: there is no party combat in dungeons at all.** The
      co-op branch exists in exactly one function, `trigger_encounter` (the overworld random
      encounter). Every dungeon path - `_start_dungeon_encounter`, `_start_dungeon_monster_combat`,
      `trigger_flock_encounter` - calls `combat_mgr.start_combat(peer_id, character, monster)`
      solo, with no party branch. The guide is supposed to fight beside you in the STARTER
      DUNGEON, so the item below has to land first. See "PARTY PLAY IN DUNGEONS".

      Also still on this list: *"party flocks are not wired"*.

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

- [x] **DONE 2026-09-13 — the monster trait table now covers every ability a monster carries.**
      23 entries added, each number read off the combat path rather than written from memory. Was
      20 entries against 95 constants; the carried, non-boss set is 39 and all 39 now have a
      description. `tools/probe/monster_trait_coverage.gd` fails if that ever stops being true,
      so the list cannot quietly fall behind a third time.
      **One claim in the original write-up was WRONG and is corrected here:** I said ambusher was
      "a guaranteed crit". It is not - that is `boss_treasure_decoy` (always, 2x). Ambusher is a
      75% chance of 1.75x on the first attack, plus +8 initiative. I had read the neighbouring
      comment rather than the code, which is the exact habit this table's rule exists to stop.
      `gold_hoarder` is deliberately left out: its constant marks it legacy with no effect since
      gold was removed, and a chip promising something the game no longer does is worse than none.

- [x] **DONE 2026-09-17 — both halves.** The card lifts and flares when played, and a ghost of
      it flies to the exact log row its effect was written into. Measured landing: **wanted
      y=279, achieved y=279**, from y=1468.

      ⛑ **HOOKED AT THE COMMIT POINT, NOT THE CLICK.** A card is playable by click OR by its
      action-bar hotkey, and the hotkey is what most people use. `send_combat_command` is where
      both routes meet.

      ⛑ **ARMED BY THE PLAY, FIRED BY THE LINE.** The result arrives through the paced combat
      queue hundreds of ms later, so the row to land on does not exist at play time. The item
      warned about exactly this (*"an animation that outruns or lags the line it belongs to will
      read as a bug"*), so playing ARMS and the first player-classified line FIRES.

      ⛑ **THREE FACTS A READ GETS WRONG, all measured first:** the visible log is
      `_battle_log_band`, not `_log_label` (which is allocated, never shown, and measures 0x0 -
      aiming at it would fly every card to the screen corner); `get_paragraph_offset()` returns
      clean 20px steps so an index really is a row; and lines carry no actor tag at the call site
      (`append_log_actor` has **no callers**), so "the player's line" is `_classify_overlay_actor`'s
      judgement.

      **Degrades as the item required:** one ghost at a time, a single Label rather than a rebuilt
      card face, freed on arrival, duration scaled by the player's combat-speed control, and the
      landing point clamped into the visible strip so a scrolled-away row cannot drag it off-panel.
      ⚑ There is **no "effects off" preference** in the game - the item assumes one exists. I
      nearly gated on an invented `combat_fx_enabled`; it failed to parse, which caught it.

      Probes: `tools/probe/card_flourish.gd`, `tools/probe/card_flight.gd`. Both sample MID-flight
      — at the end the card is back at rest and the ghost is freed by design, so an end-state
      check passes just as happily when nothing ever happened.

      Was: **THE ABILITY CARD YOU PLAY SHOULD LOOK LIKE IT DID SOMETHING.** Owner 2026-09-14:
      *"I want to add in a little more visuals to the ability card that a player select in combat.
      It would be nice for it to have a cool animation showing it is being used and then possibly
      an animation that shoots over to the combat log and lands exactly where its effects are
      populated in the log."*
      Two halves, and the second is the interesting one:
        * **the card reacts when played** - a flourish on the card itself, so the click has weight
        * **the card's effect TRAVELS to the line it wrote.** The card flies from the hand to the
          combat log and lands on the exact row its result is printed in. That ties cause to
          effect visually, which is the thing a text combat log is worst at: right now a number
          appears in a scrolling list and nothing connects it to the button you pressed.
      Notes for whoever builds it:
        * the log is a RichTextLabel; landing "exactly where its effects are populated" means
          knowing the pixel offset of the paragraph that is about to be appended.
          `get_paragraph_offset` exists and is already used by the map-sprite overlay, which had
          to `await process_frame` before reading it because layout is deferred - that await is
          the same trap here.
        * combat playback is already paced (`project_coop_playback_pacing`); an animation that
          outruns or lags the line it belongs to will read as a bug rather than a flourish.
        * it must degrade: a player who has turned effects down, or a round resolving several
          cards at once, must not end up with a screen full of flying cards.

- [ ] **ACTION POSES FOR THE 40 SPRITES THAT LACK THEM — this is ART, not generation.** Owner
      2026-09-14 asked whether a pose could be copied from a character with similar equipment.
      Measured before answering, because the instinct is half right:
        * `$tf_template.png` is a blank base body, so every character IS built on one skeleton.
          Two different characters in the same stand frame agree on **89% of their silhouette**,
          and 73% of the shared pixels differ only in COLOUR.
        * But the template carries **walk cycles only** — 12 frames, four directions, three steps.
          There is no template action pose to copy from; the sword-raises and casts in
          `expansion/animation1.png` were drawn per character on top of that skeleton.
        * So a transfer is not a copy. The 11% that does NOT match between two characters is
          exactly the part that moves: hair, cape, sleeve, weapon. When the arm goes up the
          sleeve goes with it, and that sleeve belongs to the TARGET character. Doing it properly
          means segmenting clothing from body per sprite and redrawing it in the new pose.
      **Coverage today:** `chara1-5` (40 sprites) have laugh / nod / pose / shake / surprise;
      `military1-3` (24) have pose only; `npc1-2` (16) have nothing but walk frames.
      Worth doing as authored art when there is appetite. Not worth generating.

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

## ▶ NEXT SESSION — START HERE

### ✅ COMBAT LOG REWORK — SHIPPED v0.9.803 (2026-09-18)

Owner: *"start the combat log rework. Once we get it right we can cut a new release."* Four rounds
of live testing; every item below was reported from play and confirmed fixed from play.

**The shape.** One SUMMARISED line per actor per round, built from the server's own `dmg` /
`taken` / `ability` metadata rather than by joining prose. Measured first: a three-round solo fight
emitted 12 lines, the worst two at **294 and 311 characters**, which wrapped to five or six rows
each - so the fold that already existed was trading line COUNT for line LENGTH and gaining nothing.
Each line carries its blow-by-blow as hover text, so nothing is lost.

**Round 1 — rendering**
- [x] Raw BBCode dumped on screen. The multi-line blow-by-blow was in a `[url=]` ATTRIBUTE, and a
      BBCode attribute cannot contain newlines, so the tag never closed. Keyed `_log_detail` now.
- [x] The card name vanished. `reset_round_summary()` cleared `_player_action_name`, but the round
      divider arrives AFTER the player acts and BEFORE the action lines, wiping it every round.
- [x] Only the actor's name was hoverable. *"I can't hover the 106."* Whole line is the target.

**Round 2 — attribution and reachability**
- [x] Companion merged into the player's line on a CAST and not on an attack. Two callers,
      only one marked the companion. **Fixed at the action, not the call site** - the mark moved
      inside `_process_companion_attack`, so no caller can forget it.
      Probe: `tools/probe/companion_lines_are_marked.gd`.
- [x] [L] after a fight showed the overworld. *"I only pressed L, never space."* He hadn't -
      **walking** dismissed the card. Three sites tore down the victory review and each cleared a
      different subset of its four fields; none cleared `pending_continue`. One
      `_end_victory_review()` clears all four. (The stray "Continue" reported separately the same
      day was the same fault seen from the other side.)
- [x] The log had no discoverable entry point. Added **Menu → Character → Last Fight Log**;
      [L] now asks *is there a log* rather than *is the rewards card still up*.

**Round 3 — the log becomes a panel**
- [x] It was painted into `game_output`, the label the map, location text, merchant screens and
      combat all paint into. One decision, three reported bugs: it flashed and vanished; closing it
      left the text on screen so only Space worked (*"which also forces me to rest or meditate"*);
      and keeping it up meant HIDING the combat panel, hence the victory-card gate.
      `client/fight_log_panel.gd` owns its own surface. Owner agreed: *"I'm fine with us going to a
      new Log or popup window."* The `_victory_legacy_view` bool went with it - panel visibility is
      the single answer. Probe: `tools/probe/fight_log_panel_builds.gd`.
- [x] Enemy line had no damage number. THREE causes in sequence: `message_taken` was built in
      `process_monster_turn`'s funnel against an array the solo paths never append; the solo client
      handler then dropped `taken` while copying `actor`/`dmg`/`mhp`, and only attached metadata at
      all when `actor` or `dmg` was set - so a monster line whose only number is damage to YOU had
      no metadata and fell out of the summariser entirely; and `handle_use_item` fanned its messages
      out with no tagging whatsoever. One `send_combat_result_messages()` owns the four parallel
      arrays now. **Measured end to end**: HP 889→798, `taken=91`, line renders `▸ Ogre attack ← 91`.
- [x] The card flew to the round header. The flight aims at a PARAGRAPH of the visible band and
      `_refresh_log` is what puts the line there; fired first, the index clamped to the divider.
- [x] A basic attack did not travel. `arm_card_flight` searches the HAND and gives up silently -
      always true for "attack", which is on the action bar. Added `arm_flight_from_control`.
- [x] Panel opened behind the victory card (z-index); ASCII art sheared (now Consolas).

**Round 4 — the last two**
- [x] Hover details unreachable from the log PANEL. It got `meta_clicked` and no hover wiring, so
      the links rendered and could not be used. Both halves wired, guarded by the probe.
- [x] Companion skipped round 1 against a Harpy. The Harpy is **Ethereal**; that 33% dodge branch
      returned before the companion acted. An ordinary miss already fell through, which is why this
      was the one case that looked broken. Owner's call: the companion acts when the PLAYER misses
      or is dodged, and still loses its turn to webbed / lulled / charmed / madness.

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

### ⚑ THE BALANCE BATCH — add here, run the chain ONCE

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
- [ ] **`assassinate_pct` reaches the dice** (v0.9.790). Silver Tongue +15% and one unique now work
      as written - a small per-class gain for the Trickster line. Glance at it on the next `refcal`.
- [ ] **The companion acts through an ethereal dodge** (v0.9.803). Owner waived re-calibration for
      it as too narrow to matter (Ethereal monsters, 33% of attacks). Listed so that if the batch
      runs anyway it is measured rather than forgotten - not as a debt on its own.
- [ ] **Threat bounty rewards were re-anchored** (v0.9.803). Not player power, but a reward sized
      against the board: now 0.83-1.14x the median dungeon quest where it was 0.06-0.64x. If the
      quest curve moves, re-measure with `tools/probe/threat_quest_rewards.gd`.
- [ ] **Realm-wide valor economy pass** — **written up in full at "THE VALOR ECONOMY, REALM-WIDE"**
      further down this file; that is the source of truth and step 1 is already part-done. Listed
      here only so the batch is complete. It is NOT a chain item - the chain sizes combat, and this
      sizes prices - but it shares the batch's reason for existing: `QUEST_VALOR_PER_LEVEL := 3.5`
      is an interim anchor calibrated against sinks the owner has already said are wrong, so any
      valor number tuned before it lands is tuned against a moving target.
- [ ] **Forcefield's 3-6x nerf still wants a live feel check** (from the 2026-09-02 balance day).
- [ ] **Knight +15% damage and Mentee +50% XP now reach the dice** (2026-09-18). Both were dead
      when the curve was last fitted, so the reference player has never carried either. Rare
      endgame titles only, so the effect on the aggregate should be small - but the Knight damage
      bonus lands in `calculate_damage` beside the gear multiplier, which is a path the chain does
      measure. Glance at it on the next `refcal`.
- [ ] **Are any of the 53 dungeon cards worth a deck slot?** The COVERAGE half shipped - all 53
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
- [ ] **The high-level win targets predate retreat.** 60% was chosen when a "loss" meant a death;
      it now mostly means a retreat. Revisit alongside the Unburied, since extra lives change what
      survival means. This is a question about the TARGET, so settle it before a chain run rather
      than after. (Moved here, 2026-09-18.)
- [ ] **Feel check the rest change.** `REST_HEAL_MIN/MAX` replaced EIGHT sites, so meditate and
      companion regen scaled along with rest and mages got it twice. Owner: Meditate is the
      deliberate lever if mages come back too strong - check that BEFORE touching mage design.
      (Moved here, 2026-09-18.)
- [ ] **Watch the five live characters at L3-L12.** `bash tools/check_player_progress.sh`. They sit
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

- [x] Shortcut buttons have ONE home, above the action bar, on every screen.
- [x] Party members drawn on the dungeon floor (`allies` on the wire) + the party strip underground.
- [x] Dungeon floor at 4x the area: 19x11 at 64px, from 19x9 at 32px. Two causes, both measured —
      a stale 56px headroom for the retired step counter, and `game_output` being shrunk by the
      chat log, which moved to the dungeon side column.
- [x] Real gauges (`ProgressBar` + two `StyleBoxFlat`es) for party HP/resource, companion HP and XP,
      after three text attempts were rejected. **Read `_gauge` before proposing a fourth.**
- [x] `party_update` flushes with character updates — the bars were a snapshot from grouping up.
- [x] Effects as ICONS, hoverable, no letter codes: poison/blind from `States.png`, fourteen buffs
      from `items_pack/`. **Read `STATE_ICONS` / `BUFF_ICONS` before adding more.**
- [x] Companion art trimmed of its dead rows (355 across 56 entries; the Wight 118 → 98 rows).
- [x] The sticky player/companion hover — one label, two fill mechanisms, one of them caching.
- [x] Dev loopback exempt from the connection rate limit, so a 5-client test stops losing a member.

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

- [x] **The dungeon LIST** sent the TYPE'S letter beside the INSTANCE'S number, so the label was
      assembled out of two different dungeons - while the `display_name` on the same row already
      used the instance's. Half of one row disagreeing with the other half.
- [x] **The entry warning** (new this session, so this one was mine).
- [x] **The compass bearing.** Now names the full label rather than a grade: it points at ONE
      dungeon, so it knows the rank.
- [x] **The Atlas**, all three rows. A dungeon TYPE has no single grade to report, so the Atlas
      now shows the grade of the one THIS player found - the record stores it at discovery, and
      `note_dungeon_discovery` gained a `rank` so it can keep both halves.

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

- [x] GM dungeon entry read `(T3)` — the line the owner saw.
- [x] The compass bearing read `(T5)`.
- [x] The Atlas SPOTTED row printed a bare `2` — an int interpolated straight through a `%s`.
- [x] The Atlas DISCOVERED row rendered a bare letter with no colour and no hover, against
      PowerRank's own standing rule (*"Never render a bare label"*).
- [x] The Atlas RUMOURED row said "a Tier G dungeon".
- [x] The dungeon LIST and the ENTRANCE panel both fell back to "Tier G" when no instance exists.

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

- [x] Nothing was cut - the theme-tile prose moved to HOVER, on the same `[url=tile:N]` the
      in-floor key uses. That needed a fix of its own: the resolver reads `dungeon_data`, which is
      empty until you are inside, so every glyph on the one screen where the description matters
      most was a **dead link**. Falls back to `pending_dungeon_warning` now, captured working.
- [x] The food lecture only argues with you when you have none. A warning that fires every time is
      one you stop reading.
- [x] The dungeon's RANK rides in the header (`H7`), because rank is what decides how many
      modifiers a place may roll and the owner asked for rarity to be legible before the door.
- [x] Modifiers state the trade in NUMBERS (red cost, green pay), derived from the same fields
      `modifier_effects` folds - see the axis-two entry above.
- [x] `gm_enter_dungeon` learned `warn` / `modified`, and the shots harness a `dungeonwarn` scene.
      There was no headless route to this screen at all, which is why its call site had sat
      unverified since 2026-09-13.

### ✅ 2026-09-16 — INSTANCED CARDS: the deck screen now manages CARDS, not counts

Owner: *"All classes should only start with 1 copy of each of their cards... get rid of the + on
the deck screen unless the player has two exact copies of a card (same rank, same number of uses,
same upgrades, etc.). If not all cards should appear individually... they should not both track
usage for the skill itself being used, it should instead track the number of times that unique card
has been used."*

**Two of the three were already true, and that was MEASURED before changing anything**
(`tools/probe/deck_starts_with_one.gd`):

- [x] **Starting copies are already correct.** All nine classes: 5 cards, 5 copies, no duplicates.
      The earlier fix the owner remembered is `repair_deck_once()` (commit `3ac2e08c`), which
      repaired deck SIZE on live saves (6-13 cards against a designed 5) — a different number.
- [x] **Use tracking is already per-instance.** Proven both ways: a cast addressed by instance id
      (`record_mastery_use(hand_key)`, which is what combat does) and a bare-name cast while the
      active instance is announced. Both land on the copy, neither on the shared card name.

**The deck screen was the real gap, and it is fixed:**

- [x] One tile per INSTANCE, always. It used to split a card only when more than one copy was
      owned, and then split every copy unconditionally.
- [x] Identical copies STACK into one tile with `×N`. "Identical" is `_stack_signature`: mastery
      rank, exact use count, milestone picks (sorted), effect rank, and in-deck state. Uses are in
      there deliberately — two rank-1 copies at 12 and 40 uses are not interchangeable.
- [x] `−` and `+` address the SPECIFIC copy. Both bound the bare card name before, so `−` on
      "copy 2" asked the server to bench whichever copy it liked. `cull_ability_card` already
      accepted `cleave#2`; the key just had to be sent.
- [x] The permanently-disabled `+` is gone. It appeared on every card, unpressable, to explain
      where copies come from.
- [x] Tiles read "In deck" / "In deck ×N" / "Benched" instead of "Deck × 1/3", and the draw strip
      shows one tile per physical card rather than N tiles each labelled `×N`.
- [x] `gm_card_copies` + `--shots=deckcopies` reach the state on demand: a card whose copies differ
      AND a card whose copies match, in one frame (`shot_11668`). Verified 4/60/250-use Cleaves draw
      as three tiles at R0/R2/R3, and two 7-use Venom Fangs as one `×2`.

- [x] **Existing characters keep their duplicate roster cards — owner decided 2026-09-16:**
      *"I'm not concerned with current characters you can leave those as is."* No second
      `repair_deck_once` pass, which also means nothing is written that could delete an earned
      dungeon or companion card. New characters already start with one copy of each (measured
      across all nine classes, `tools/probe/deck_starts_with_one.gd`).
- [x] **Your Deck is a card GRID**, built by the same `_make_deck_entry` as the collection, so the
      two halves read as one screen you move cards between. It scrolls, and so does All Cards.
- [x] **A card is in ONE half, never both.** That is what makes the gesture unambiguous. The old
      screen listed everything in the catalogue and *also* mirrored in-deck cards into a strip, so
      a card appeared twice and dragging the catalogue copy of a card already in the deck would
      have meant nothing.
- [x] **Drag up to play, drag down to bench.** Two inner classes (`CardDrag`, `CardZone`) - Godot's
      drag/drop is virtual methods on a Control, so a runtime-built tile cannot take part without a
      script. The payload carries the exact copy key, so a drag moves the card you grabbed.
- [x] **The −/+ buttons stay.** A drag is invisible until you try it; the project's own rule is
      that the discoverable control comes first and the gesture is a supplement. Both paths end in
      the same two signals.

- [x] **THE GESTURE IS VERIFIED BOTH WAYS, by synthesised input.** `--shots=deckdrag` presses on a
      card, moves past the drag threshold and releases over the other zone, then asserts the card
      actually changed halves. Both directions PASS with `drop: 1`. It is a regression test, not a
      one-off: run it after anything that touches this screen.

      **It also found the two causes that reading the code had missed, and the counter pattern is
      what named each one:**
      - *all three counters zero* → the drag never STARTED. Godot asks for drag data from the
        control that TOOK THE PRESS and does **not** walk up for a parent that implements
        `_get_drag_data`. A wrapper can never be a drag source. The card watches its own
        `gui_input` and calls `force_drag` instead.
      - *`drop` missing, the others firing* → the drop WALK broke. Godot finds a drop target by
        walking up from the cursor and **stops at the first `MOUSE_FILTER_STOP` control**, so the
        tiles were swallowing every release. Everything inside a zone is demoted to PASS after each
        rebuild (`_open_zone_for_drops`) - a PASS control still receives its own input, it just
        stops ending the search.

      ⛑ **Any STOP control inside a drop zone is a dead patch** where a release silently does
      nothing. That is how the collection zone failed one run and passed the next: the probe aimed
      at the zone's centre, and the centre landed on different content each time. Dead patches you
      can only find by aiming at them are worse than a total failure - which is why the fix sweeps
      the whole subtree rather than naming the controls that were STOP that day.

### ⛑ NOT VERIFIED IN v0.9.795 — look at these first

- [x] **The dungeon key's tile hover.** VERIFIED 2026-09-16. Label on screen at 1343x22, mouse
      filter receives events, and its text carries the theme mark (`f Wyvern down`, a
      `[url=tile:0]`). Driving `tile:0` raises the popup. Scene: `shots.py hoverproof`.
- [x] **The buff-icon hover popups.** VERIFIED 2026-09-16. Poison applied via `gm_apply_state`,
      the Effects box renders the icon (confirmed in the capture, not from the text - an `[img]`
      contributes ZERO characters to `get_parsed_text()`, so length proves nothing here), and
      `fx:poison` raises the popup.

      **⛑ The instrument that did NOT work, recorded so nobody rebuilds it.** The first three
      attempts drove a SYNTHETIC MOUSE - `InputEventMouseMotion` pushed through the viewport,
      sweeping each label's rect. It never once produced `meta_hover_started`, including over a
      link written for the purpose. Three separate false readings came out of it before a control
      caught it: sweeping `game_output` **underground**, where the dungeon renderer hides it;
      reading `lbl.text` for `[url=` when every label here is filled with `append_text()`, which
      parses without ever writing that property; and reading a 10-character Effects box as empty
      when the icons were there all along. Do not retry synthetic hover without first making a
      control answer.
- [x] **ONE canvas size only.** — ANSWERED 2026-09-16, and the concern does not materialise.
      **Every plausible window shape draws the floor at 64px.** Only the ROW COUNT moves, 7 to 15.
      The reason is structural: the game stretches with `canvas_items` + `aspect=expand`, which
      pins the viewport WIDTH at 1920 and lets only the height track the window's aspect - and the
      tile is chosen from the width. A 16:9 window of any resolution is the same viewport.

      | aspect | viewport | floor |
      |---|---|---|
      | 16:9 | 1920x1080 | 64px, 11 rows |
      | 16:10 | 1920x1200 | 64px, 13 rows |
      | 21:9 | 1920x823 | 64px, 7 rows |
      | 4:3 | 1920x1440 | 64px, 15 rows |
      | 32:9 | 1920x540 | 64px, 7 rows |

      The 64px step needs a canvas 1240 wide (viewport 1793) and the viewport is always 1920, so
      there is 127px of headroom - **a future layout change that eats more than that halves the
      floor**, because the step below 64 is 32 and shows a quarter of the area. That is a cliff,
      not a slope, and the probe asserts it.

      **⛑ The obvious way to check this was impossible, and cost four runs to find out.** Running
      the harness at several resolutions clamps: `--screen 1` targets a 1920x1080 monitor whose
      WORK AREA is 1920x1032, so every taller or wider window was squashed back to the same 1009
      and four "different" runs measured one shape four times. The fit maths is now a pure static
      `Client.dungeon_tile_fit`, so `tools/probe/dungeon_tile_fit.gd` answers it **headlessly** -
      no window, which is also the answer to *"do you keep opening a client?"*

### Open, in order

- [x] **Blinded, the overworld map is a 5x5 cross at 30px** — DONE 2026-09-16. Measured before and
      after in one run: sighted **23 cols at 29px** (unchanged), blinded **5 cols at 64px** (was 29).
      The fix is a LADDER, not a bigger cap: the art is 32px, so a raised cap would have drawn a
      normal 23-wide view at 51px and smeared every tile at 1.6x. `_overworld_crisp_px` returns a
      whole multiple of the source when there is room, the source size when there is not, and the
      existing shrink-to-fit below - so only a view small enough to afford a clean 2x moves.
      Stops at 2x deliberately (`_OW_MAX_UPSCALE`); the same view would take a clean 7x and five
      enormous squares read as a bug rather than as reduced vision.

      **⛑ Three false readings before the number was trustworthy**, all in the harness: the scene
      WALKED to trigger blind vision, which `send_location_update` only applies on a move that
      SUCCEEDS and the spawn is hemmed in - a trap already written down in the party scene that I
      walked into anyway; blindness PERSISTS on the character, so the second run opened already
      blind and filed a 5x5 map as the sighted control; and the diagnostic print was invisible
      because shots.py only echoes lines carrying `[SHOTS]`. The scene clears state first and
      reports blind flag and column count beside the tile size now, so a wrong reading says so.
- [x] **⛑ TWO COMBAT EFFECTS THAT DID NOTHING** — FIXED 2026-09-16, owner picked it.

      An Eternal player's Smite did `target.add_buff("smite_debuff", 25, 10)` with the comment
      *"-25% damage for 10 rounds"*, and that line was the **only reference to the key in the
      entire codebase**. The poison half of Smite worked; the damage half had never existed.
      `damage_penalty` was the mirror image - an icon, a colour, a label and help text on the
      client, applied and consumed nowhere.

      Smite now writes `damage_penalty`, and both damage funnels consume it.

      **It goes in the FUNNELS, not beside the buff reads.** The five
      `get_buff_value("damage")` sites are per-ability - magic bolt, blast, cataclysm, unmaking,
      basic attacks - so a penalty placed there would have reached five cards and silently missed
      every other one, which is a subtler version of the bug being fixed. It goes in
      `apply_ability_damage_modifiers` (documented as covering all ability damage, solo and party)
      and in `calculate_damage` (basic attacks) - the same two places `analyze_bonus` is applied,
      for the same reason. The CARD PREVIEW got it too, or a smited player reads a number the
      fight will not pay.

      **The tempting one-liner is wrong, and it is worth knowing why.** Reusing the `damage` key
      with a value of -25 READS correctly, because `get_buff_value` sums - but `add_buff`
      refreshes an existing entry with `max(buff.value, value)`, so a -25 arriving while War Cry
      is up is thrown away and the player takes no penalty at all. A separate key is the fix, not
      tidiness.

      **Measured, 4000 samples each:** abilities 24.9%, basic attacks 25.2%, against the 25% the
      ability claims. Proven to fire by restoring the dead key.
      Probe: `tools/probe/smite_damage_penalty.gd`.

      **⛑ Two instrument faults on the way, both mine.** The probe first called the funnel ONCE
      each and read 1250 against 750 as a 40% cut - that funnel ROLLS (abilities crit, and glance
      for 60% on a failed accuracy check), so one call against one call compares two dice. And it
      grepped for the string `smite_debuff`, which failed on the very comment explaining the fix;
      it looks for the WRITE now.

      **⛑ And a real finding from the measurement: `int()` truncation made the penalty harsher
      than advertised.** At a level-20 basic attack of ~18 damage, truncating sheds half a point
      every swing and a "25%" penalty landed at 29.8%. Abilities hide it because their numbers are
      large. Rounded instead, which is why the attack path now measures 25.2% rather than 30.

      **No re-calibration needed, and that was checked rather than assumed:** this only changes
      damage while `damage_penalty` is active, which happens solely through an Eternal's PvP
      Smite. The reference player the monster curve is built from never carries it, so
      `speciescal`/`refcal`/`rolecal` are unaffected.

- [x] **Buff icons for the rest.** — DONE 2026-09-16, and it was **three keys, not "the rest"**.
      Diffed every `add_buff(...)` call in the game against `BUFF_ICONS`: only
      `open_guard_penalty`, `time_stop` and `smite_debuff` were applied with no picture.

      **None of them needed new art.** `smite_debuff` became `damage_penalty` when Smite was
      fixed, which was already mapped. `open_guard_penalty` means the same thing as
      `defense_penalty` - you take more damage - so it takes the same shield. And the item pack
      already contains `Hourglass.png`, which is a literal hourglass for an effect that stops the
      next attack. The standing rule in `BUFF_ICONS`' own note is not to press a spare DEBUFF ROW
      into service as a buff; reusing an icon for the SAME MEANING is a different thing.

      **⛑ And a two-copies-of-one-number retired on the way.** `open_guard_penalty` is stored
      with a value of 15 and its consumer multiplied by a hardcoded `1.15`. They agreed, so
      nothing was broken - but the hover added here quotes the STORED value, so the moment either
      moved the screen would have lied. The consumer reads the stored value now.

- [x] **Every effect icon is LOADED, not looked at** — new guard, 2026-09-16.
      `tools/probe/effect_icons_load.gd` calls `load()` on all 16 buff icons, loads the state
      sheet, asserts each state frame sits INSIDE it (a frame running off the edge samples empty
      pixels and draws a blank square, which reads as a missing icon and sends you hunting in the
      wrong place), and re-diffs applied effects against the table so a new one cannot ship
      iconless. Proven to fire against both fault shapes: a path that does not exist, and an
      applied effect with no entry.

      Also a `buff_icons` line in the release gate, per CLAUDE.md's rule about new art surfaces.
      **⛑ The first version of that line would have failed EVERY release:** it printed
      `buff_icons=true (16/16)`, and `verify_release_build.sh` parses with
      `sed "s/.*name=//" | tr -d ' '`, so the value arrived as `true(16/16)`. The count is on its
      own line now. Caught by reading the parser rather than by a failed release.

- [ ] **Judge the dungeon with a full party.** The owner has frames at the right tile size now
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
- [x] **The dungeon canvas got its 130px back, and the floor grew to 1216x704.** The canvas was 662
      tall underground against 792 up top, and the missing height was in BottomStrip (h_min 256 vs
      126) — the chat log moving there is what claimed it, so the FLOOR was paying for the chat box
      out of its tile size. Underground the chat now goes in the dungeon's own side column, which
      carried the floor status in its top third and nothing in the other ~680px. A fight and the
      Sanctuary room still send it to the bottom strip. Measured after: `h_room=718 tile=64 rows=11`.
- [x] **Effect ICONS for poison and blind**, hoverable, with `gm_apply_state` + `--shots=states` to
      photograph them on demand. **Read `STATE_ICONS` in client.gd before adding more:** the sheet is
      ten DEBUFF states with no positive buffs, the frame is deliberately FIXED (half the animation
      cycle is invisible at chip size — measured, 801 opaque px down to 90), and the region is the
      mark's tight bounds because the mark is only ~35px of its 96px cell.

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

- [x] **DONE 2026-09-17 — hidden on the keypress, and the cause was the server round trip,
      not the frame ordering.** Was: *"Market and alchemy crafting still display Travel stances for a brief second before it hides
      when they are opened, the stances need to hide before those menus are drawn, not after."*
      ☑ **MEASURED 2026-09-17, and the answer moves the item.** New shots scene `stancetiming`
      prints a PER-FRAME timeline (a row only when something changes) of the stance bar, the
      shortcut row, both panels and `_margin_widgets_shown()`, driving each entry the way the game
      really reaches it.

      ```
      market     f0     0ms  stance=false shortcuts=false marketpanel=false market_mode=true
      market     f1    31ms  stance=false shortcuts=false marketpanel=true  market_mode=true
      alchemy    f0     0ms  stance=false shortcuts=false craftpanel=false  crafting_mode=true
      alchemy    f1    32ms  stance=false shortcuts=false craftpanel=true   crafting_mode=true
      ```

      ⚑ **THE ORDERING IS ALREADY WHAT THE OWNER ASKED FOR.** The stances and shortcuts are gone
      on the frame the mode flips, and the panel is drawn on the NEXT frame - hidden BEFORE the
      menu is drawn, not after. So the two previous fixes worked; they fixed a real frame-lag that
      was not what the owner was seeing.

      ⚑ **WHAT THE OWNER IS SEEING IS THE ROUND TRIP BEFORE ANY OF THAT.** Bump-to-interact is
      entirely server-side: the client sends `move`, `server.gd:5624` sees the target tile is a
      `market` or a station, sends back `market_start` / `station_interact` and **returns without
      moving the player**. Until that reply lands the client has no idea anything is happening, so
      the map, the travel row and the shortcuts all correctly stay exactly as they were. Measured
      RTT to the live server: **71ms** (5 pings, 70-72ms), plus a client poll frame and a server
      tick either side - call it **90-120ms, six or seven frames**, during which the player has
      pressed a key and nothing at all has changed. Then everything changes at once.
      That is a much better fit for *"a brief second"* than any within-frame ordering, and it
      explains why two ordering fixes changed nothing the owner could see.
      It also explains the owner's PAIRING of market and alchemy: both are entered by bumping a
      tile (`market`, and an alchemy station via `station_interact`), so both flip their mode only
      on the reply. Crafting opened from the menu (`open_crafting`, a local action) flips
      immediately and has never had the problem.

      ☑ **BUILT 2026-09-17. Owner, given the measurement and the choice: *“Yes - hide on the
      keypress.”*** The client now guesses, because it can: `send_move` is the single place a
      player's move leaves the client, and the map payload's `meaning` grid already carries the
      tile TYPE of every visible square. If the next square opens a menu, the margin widgets go
      immediately and the server's reply ends the guess (with a 500ms hard expiry, so a reply the
      list does not recognise cannot hide the row forever). The owner accepted the failure mode
      explicitly: a refused bump blinks the travel row off and back within ~100ms.

      ⚑ **TWO TABLES, ONE OWNER EACH, because both are the copy-shape this project keeps paying
      for.** WHICH TILES open a menu is the server's `elif` chain in `handle_move`; WHICH WAY each
      direction id goes is `move_player`. Both now live in `shared/world_system.gd`
      (`MENU_ON_BUMP_TILES` + `opens_menu_on_bump`, and `MOVE_DELTAS`, which `move_player` reads
      instead of its own nine-arm match), and the station half is read from
      `CraftingDatabase.STATION_SKILL_MAP` rather than retyped.

      ⛑ **I wrote the client's direction table from memory and every entry was wrong** — 0-7,
      against the game's numpad 1-9 with 5 as stay. The mask would have read the wrong square on
      every move and presented as the feature simply not working. That is why `move_player` now
      reads the table rather than the table being a second copy of `move_player`.

      ⛑ **And the tile list was missing three** — `guard`, `throne`, `signpost`. I read the
      server's chain and stopped three lines early; `tools/probe/menu_bump_tiles.gd` caught all
      three on its first run, which is the argument for the guard rather than the list.

      ⛑ **The probe's first direction check was CIRCULAR and the injection proved it.** It
      compared the table against `move_player` — which now reads the table — so flipping north to
      point south produced zero failures. A single-owner value cannot be checked against itself.
      It is checked against two INDEPENDENT statements of the same fact now: `move_player`'s own
      docstring (which spells the numpad out in words) and `_get_direction_text` (which turns a
      delta into a compass word and carries its own copy of *world y grows north*). Both fire on
      the flip.

      ⛑ **And one of my injection tests silently did nothing** — the replacement string had the
      wrong number of spaces and the script had no assert, so “the check does not fire” was itself
      a false reading. Second time this session. **Every fault injection asserts that it landed.**

      Instrument kept: `--shots=stancetiming`. Re-run it after any change to the margin rule.
- [x] **Icons for the effect chips — SHIPPED v0.9.795/796.** Poison and blind come from
      `States.png` (copied out of a `.gdignore`d pack, which is its own recorded trap), and
      fourteen BUFFS got icons from `items_pack/` - sword, shield, armour, boots, star, heart,
      spike, rune, cloak, all literal. Chips are icon-only with the value and duration on hover.
      Unmapped effects keep a lettered chip; see `BUFF_ICONS` before adding more.
- [x] **Dungeon and party-combat screens — REVIEWED WITH THE OWNER 2026-09-16** across several
      rounds of captures (party dungeon at 64px tiles, party combat, the completion screen). What
      came out of it is recorded in the v0.9.795/796 blocks above.
- [x] **DONE 2026-09-17 — SEEN in both, which is what the item asked for.** Captured a dungeon
      floor and a combat round: the hotkey pills (`Space Q W E R 1 2 3 4 5`) are present and
      styled in both, and the shortcut row carries into the dungeon too. The worry was unfounded
      — but it was the right worry, and the only way to retire it was to look. Was: one styling
      function, so they should carry over, but they have not been SEEN there.

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
   **MEASURED 2026-09-15** (`tools/probe/equipment_audit.gd`, `tools/probe/items_in_combat.gd`; every
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
   - [ ] **NOT SEEN IN PIXELS: the dungeon key under the map.** Every `--shots=dungeon` run on this
     character lands in a Troll ambush, so the captures show the fight, not the floor.
   - [ ] Still open here: the companion art panel in the right margin has no frame; and a TEXT page
     on the canvas is still overwritten by the next map redraw (a visual panel is not - it sits on
     top). Movement is blocked in most such modes, so it needs a party-member push to show.
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
   - [ ] **STILL OPEN: the DUNGEON side panel** (*"their area on the right for where the dungeon
     text goes is pretty cramped"*). Same column, different mode; needs a live dungeon session to
     measure, since an empty client gives that panel the whole column.
   - [ ] **Needs an eyeball**, not a number: whether 16px Tools / the resulting map size actually
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
6. **First-hour polish, all small, all seen by every new player:**
   - the Warden's handout is named like endgame loot (needs a plain-base-item path, below);
   - ✅ DONE on master 2026-09-15: **"Floors Cleared: 2/5"** on the starter dungeon. Five places
     asked the dungeon TYPE (5) for the instance's floor count (2): HUD, floor messages, go-back,
     completion screen - and the **Floor Skip Charm**, which on the real boss floor spent the charm
     and skipped the boss to its final chest. One helper `_instance_floor_count` now. XP still
     divides by the type's count (owner: fix the text, keep the tutorial's pay). A refused charm is
     now refunded. Probe `instance_floor_count.gd`, proven red on the old code;
   - roads 3 wide -> 2 (owner, 2026-09-14; note the encounter corridor narrows with it).
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

- [x] **Co-op monster debuffs: SHARED — owner decided 2026-09-16, built.** `monster_charmed`,
      `monster_weakness` and `monster_slowed` (and their durations) now sit in
      `_PARTY_SHARED_MONSTER_KEYS`, so a debuff one member lands protects the whole party rather
      than only its caster. They are ALSO in `_PARTY_DOT_KEYS`, which is the half that is easy to
      miss: the monster acts once per MEMBER, and all three tick down inside that turn, so shared
      without de-duplication would spend a 1-turn charm on the first member and expire a 2-round
      weakness in one round of a four-party. The magnitude keys are deliberately NOT de-duplicated
      — zeroing those per action would remove the debuff from everyone after the first, the
      opposite mistake. `tools/probe/coop_shared_debuffs.gd` asserts both halves.
- [x] **Text-map fallback draws no gold ring or arrow** — **DONE 2026-09-17.**
      `_render_overworld_room` worked out `mark_cell` and `mark_arrow` and then, when the sprite
      renderer declined, returned a bare `MapPayload.inflate(payload)` — which has never heard of
      either. So with sprites switched off, or in a build missing licence-restricted art, the
      Warden said *"it is ringed on your map"* and nothing was ringed anywhere.
      New `MapPayload.inflate_marked(payload, mark, arrow, w, h)` draws it, in the renderer that
      already owns what a payload MEANS rather than in the client. Two deliberate choices:
      the on-grid ring is a gold **background** so the cell's own glyph survives (the marked tile
      is usually the dungeon `D` being pointed at — a marker that overwrote it would point at a
      thing by deleting it), and the off-grid arrowhead **replaces** its cell, because four tiles
      from the player the direction is the whole message.
      `w`/`h` pick the MAP grid rather than the first grid in the payload: a payload holds a
      minimap too, and marking that one would put a gold cell in the corner inset and nothing on
      the map. Probe `tools/probe/text_map_mark.gd` checks that case explicitly, along with the
      row (this codebase has got the map's inverted y axis wrong twice) and a no-mark control that
      must come back byte-identical to the plain renderer.
- [x] **The text overworld map is RETIRED** — **DONE 2026-09-17.** Owner, asked whether the
      sprites-off path was still worth supporting: *"Retire the text map."*
      Gone: the settings toggle, the saved `overworld_sprites` setting, the settings row, the
      `_toggle_overworld_sprites` handler and every `if overworld_sprites` branch. **One supported
      overworld renderer** — no duplicate path to keep in step, no "which map am I looking at"
      class of bug, one fewer setting for the controller/phone simplification, and the
      corner-label occlusion below is now unreachable in normal play.
      An old settings file carrying `overworld_sprites: false` is simply ignored, which is the
      point. The row is left OUT rather than renumbered (slot 7 is a gap): those numbers are typed
      from muscle memory, and the UI audit renumbers the whole screen at once or not at all.
      ⛑ **What is KEPT, and why it is not a half-measure.** The sprites are licence-restricted and
      live in a separate private repo, so a source build legitimately has none — deleting the last
      resort would hand that case a **blank** map rather than a letter map. So it still falls back,
      and it is no longer silent: it names the cause where the map would be. The accepted cost
      (*"licence-restricted art missing from a build becomes fatal rather than degraded"*) is
      applied at the **release gate** instead, as a new `overworld_art` check — which is where
      fatal belongs, at the build, rather than in front of a player who cannot do anything about
      it. Verified: `[BUILDVERIFY] overworld_art=true`.
- [x] **CLOSED 2026-09-17 by measuring it — it describes a configuration that no longer exists.**
      The item asked for *"the screen measured, not the code reasoned about"*, so:

      * **Captured all three states it names.** In a **dungeon** the right column is the run log and
        there is no overworld map on screen at all; in **combat** the battle scene fills the screen,
        same. Neither shows a Coords or Area box anywhere.
      * **Measured the rects** (`tools/probe/map_widget_overlap.gd`) in the exact layout the item is
        about, the one `_place_map_widgets(false)` builds: each box is **240x52 = 1.1% of the map**,
        at the top-left and top-right — and **both are not visible** there, so real coverage is
        **0%**. The derived estimate this item carried (*"the top four rows of about a third of the
        width at each corner"*) was in TEXT-CELL terms and was several times too big; it was
        describing the retired text map.

      ⛑ **AND THE PROBE'S FIRST RUN WAS WRONG IN THE FLATTERING DIRECTION.**
      `coord_post_label` is built lazily by `_ensure_coord_post_label()` on the first location
      update, so headless it was simply **null** — the probe printed "(absent)" and then a
      confident **0.0%** for a box that did not exist. A measurement that silently drops one of the
      two things it measures is worse than none. It builds both before measuring now.

      Was: **The Coords/Area boxes can cover the corners of the map** — **re-scoped 2026-09-17, and it
      was never really about the ring.** Read off `_place_map_widgets`: on the sprite canvas — the
      only overworld renderer now — those boxes live in the **margins beside** the map, so there is
      nothing to occlude. They *"float over its corners"* only when the map is drawn into
      `map_display`, which `_ow_canvas_eligible()` selects while in combat, in a dungeon or in the
      house. Retiring the text map removed the configuration this was originally filed against.
      The geometry in the remaining case, derived and still not measured in pixels: each box spans
      x 8 to 8+`margin_w` (default 240) and y 8 to 60, so at a ~7x14 text cell it covers roughly
      the **top four rows of about a third of the width at each corner**. Which makes the honest
      item bigger than the gold ring — it hides part of the map itself.
      **Deliberately not fixed here.** Deciding where they should go needs the screen measured,
      not the code reasoned about, and the overworld map is barely the thing a player is looking at
      in those three states. For the UI audit, with a capture.
- [x] **The ring, the walk and the bearing could all name different tiles** — **DONE 2026-09-17,
      and it was worse than this item said.** Filed as needing *two* unfinished starter dungeons.
      It needed one, and there were **three** owners of the destination, not two:
      * the **mark** (`_mark_the_dungeon`) picked the nearest starter instance, falling back to
        `_find_nearest_dungeon_for_quest(..., 3)` when there was none;
      * the **walk** (`_escort_walk[peer_id].gx/gy`) froze a goal at walk start;
      * the **bearing** in the side panel (`_escort_goal_for`) re-picked every single step and had
        **no fallback at all** — so with no starter instance the ring pointed at a tier-3 dungeon
        while the panel said nothing and the Warden refused to lead.
      Any step that changed which instance was nearest moved the bearing off the ring and off the
      walk. **Fixed structurally:** one `_starter_destination(peer_id, character)` that both the
      ring and the bearing ask, and **once he is walking the walk is the truth** — the bearing
      reads the active walk's goal instead of re-picking, so it counts down to the tile he is
      actually carrying the player to. `_escort_walk_start` now re-sends the mark on both its
      paths (the mark lives only in client memory and expires after 900s, so a player who took a
      while to read the panel set off toward an unmarked tile) and records the dungeon's NAME so
      the bearing can name it. `tools/probe/guide_ring_and_delivery.gd` gained a section that bans
      a second picker.
- [x] **"Floors Cleared: 2/5" on the starter dungeon's completion screen** - fixed, see RECOMMENDED ORDER item 6.
- [x] **Home is the NEAREST post** — **ASKED AND CHANGED 2026-09-17.** Owner, given the choice:
      *"Back to where you started."* So it is `character.origin_post`, stamped once at creation,
      with nearest kept as the fallback for legacy characters who have none. The line he SAYS at
      the end of the chain reads the same field, or he would ring one place and lead to another —
      the same three-owners split fixed for the outbound leg the same day. Driven on the live
      server in `tools/probe/tutorial_walkthrough.gd`, including the legacy fallback.
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


- [x] **The Warden's handout is named like endgame loot** — **DONE 2026-09-17.** *"Rusty Weapon
      of Wisdom"* is *"Rusty Weapon"*, and the kit is deterministic instead of a fresh roll per
      character. The `plain` path in `_generate_item` this entry asked for exists; the level moved
      5 → 10 to pay for the dropped affix, measured at 1.04x of the old kit's power.
      ⛑ **AND THIS WAS THE SAME JOB AS "THE STARTER KIT IS STILL NAMED LIKE ENDGAME LOOT"**, filed
      separately under another name — same function (`get_starter_kit_item`), same cause, same
      requested fix, two open lines. Exactly what the backlog rule at the top of CLAUDE.md is for.
      Full write-up under that heading; probe `tools/probe/starter_kit_plain.gd`.


Fixed this pass (`bdd7060c`, `adef56ab`, and the party-kill/import commit):
- [x] **Party kills never credited a kill quest.** `_end_party_combat_all` never called
      `check_kill_quest_progress` / `record_monster_kill` / the bestiary. Affected ALL co-op, not
      just the tutorial — the tracker sat at 0/1 after the wolf died.
- [x] **A re-bake never reached the screen.** Godot only re-imports on an editor pass; the bake
      script now reports which files the game will still draw stale.

Still open from that same report, in the order they block a new player:

- [x] **The Warden follows you on the map.** Drawn as a FIGURE at player scale in the cell behind you, and hidden from the post while he escorts (per-player `pass_through`).
- [x] **Warden sprite in party combat.** The `?` was an empty name from resolving NPCs out of the peer map; underneath, he was class "Warrior", which does not exist.
- [x] **Combat taught step by step.** Hover, click or number key, Space as the free fallback; rings the cards AND their hotkeys; no longer promises traits a wolf does not have.
- [x] **Party lock-in removed entirely.** Picking a card submits; "Change action" withdraws until the last member picks.
- [x] **Nothing makes the player equip the sword** — the Warden now refuses the step out of
      the post while the blade is still in the pack, and only while it IS in the pack, so nobody
      can be stranded behind a door waiting for an item they do not have.
- [x] **The "+ is the door" line is wrong** — the overworld is all sprites now, there is no `+`.
- [x] **Sanctuary wording fixed** — names the real stations and the Door.
- [x] **Player sprite draws water under it on a cleared tile** — `_marker_with_tile` reported the
      raw tile type and never consulted the depleted set, so the ONE cell that could show the
      fault was the one always under the player. Probe: `standing_on_a_spent_node.gd`.
- [x] **Victory now teaches recovery** — Rest, food cost, where monsters are met, travel stances.
- [x] **Tutorial fight cannot flock.** Gated on the guide being present.


### ⚑ ONBOARDING — fixed 2026-09-14, UNRELEASED, and one piece still open

Owner tested a fresh account locally and reported five things. Four are fixed on master
(`bdd7060c`, `adef56ab`), proven by `tools/probe/guidance_points_somewhere.gd` — every section of
which was verified by injecting its own fault.

- [x] **The Warden drew as a letter.** `bake_overworld_tiles.py` writes his art from its own
      function, then derived "which tiles still need a glyph" from the `CUTS` table, which he is
      not in — so the fallback pass overwrote his sprite with a rendering of "W". `have_art` is
      now derived from what the run actually WROTE. Three probe versions were needed before the
      check was sound; see the commit message, it is a compact catalogue of instrument defect.
- [x] **The movement lesson fired after character creation.** It was never moved: the keypad
      diagram opens on character ENTRY and always had. The Sanctuary intro now asks for it
      (`show_movement_help`), and character entry no longer does.
- [x] **Nothing pointed at a named button.** `client/ui_spotlight.gd` rings any Control the game
      has just named, once the popup closes rather than underneath it. Hints carry a `highlight`
      list; shortcut buttons are named for their action id so they can be addressed at all.
- [x] **His dialogue ended with no next action** — *"I pressed got it on his dialogue and now I'm
      just standing here."* Equipping the blade now fires `_maybe_warden_next_step`, which says
      the post is walled and which compass direction the door is.

- [x] **DONE, shipped v0.9.789 — the Warden is visible while he escorts you.** He is drawn as a map FIGURE at player scale, and on step three he stands on the side the dungeon is on so you can simply follow him. (2026-09-15 follow-up: he now WALKS you there and puts you on the tile.) ~~Was:~~ **the Warden is still invisible when he escorts you.** Owner: *"I walked out of the
      post, the Warden didn't follow me, there was no indication he actually joined me or where I
      should go."* He only materialises at combat start (`_start_guided_overworld_combat`); he is
      not a map figure and not in the party panel. The map payload is built in `world_system.gd`
      (three `"figures"` return sites) which knows nothing about the escort, so this needs an
      escort flag threaded to the client. The companion already takes the trailing cell via
      `_trail_offset`, so the flank cell beside the player is free for him.

- [x] **DONE — verified removed 2026-09-15.** `client.gd` now carries a comment at that spot explaining the branch was a DECOY: starting a party fight sets BOTH flags, so `elif in_combat:` always won and the real case is handled by `party_round_submitted and party_combat_active` ABOVE it. ~~Was:~~ **`party_combat_active` still sits after `elif in_combat:`** in the client action bar
      (~9938). The sibling branch `party_confirm_pending` was moved above `in_combat` to fix
      co-op lock-in; this one was left and is likely unreachable for the same reason. Check
      before the next release — it is the same defect that made every new player's first fight
      impossible to lock in.


**SUPERSEDED — v0.9.789 has been live since 2026-09-14; see the top of this block for the current state.** The notes below are kept for the deploy-verification detail. **v0.9.783 IS LIVE** (server hash-verified `074c338c`) - hunting grounds, and the danger guard
taught to read what actually spawns. **v0.9.782 IS LIVE** (server hash-verified `6def650b`, seven assets on the tag, Windows gate
passed, no script errors). It carries the blindsiding guard, the map level hover, and the
who-is-online feed. Next up in this block: hotzones.


**v0.9.781 IS LIVE.** Server deployed and verified by hashing the RUNNING process (`3d204cf9...`),
seven assets on the tag, Windows gate passed, no script errors. v0.9.780 shipped earlier the same
day (the dungeon grade lie, the world reshape, the lag, the one-time relocation).

- [x] **WHO IS ONLINE — DONE. Discord half is LIVE and verified.** Owner: *"a tool that is
      efficient and doesn't use much data that shows the players currently online...
      viewable from my android phone and in discord."* The server EDITS one Discord message
      every 3 minutes (name, level, class, where), self-heals if that message is deleted,
      and logs every failure. `docs/status.html` is the web half, linked from every page,
      reading a public gist. **Owner input needed:** a gist-scoped GitHub token for the
      server to write with - the `gh` CLI token would work but carries full repo scope,
      which should not sit on a game server.

### ⚑ OWNER DECISIONS 2026-09-13 (second batch)

- [x] **BLINDSIDED BY HIGH-LEVEL COUNTRY — DONE, unreleased.** Both halves: hovering any
      map square reports that ground's level, and a step onto country at 2x your level is
      refused once (press again to go). Two real faults found in the hover, which had been
      written and never run: your own square disagreed with the Area tag, and edge blocks read
      ground outside the view. Verified in a running client, not just probed.
      ~~Original ask:~~ Owner: *"now that roads are safe
      and areas level moves around a bit we need to make sure players aren't blindsided by high
      level areas. We should either warn players before they enter a level much higher level than
      them or make it where players can hover an area of the map to see the area level."*
      This is a direct consequence of two things I shipped: regional menace deliberately broke
      "distance means danger", and safe roads encourage crossing ground nobody scouted. The
      `Area: Lv ~N` readout warns about where you ARE; nothing warns about where you are GOING.
      **Do BOTH** - hovering a map square to read its level is the tool, and a warning on
      stepping into country far above you is the guard for players who do not hover.
      The `[url=]` hover mechanism from v0.9.778 already carries per-square data; this is the
      same shape.

- [x] **HOTZONES -> RICH HUNTING GROUNDS — DONE, LIVE in v0.9.783.** They move every 3 hours
      (epoch folded into the coordinate hash, so no table and no persistence), are fewer and
      bigger (typically 37 tiles, never under 13, same 2.64% coverage), spawn 10-30% elites, and
      the screen leads with the reward instead of "DANGER ZONE - stay back". Measuring them first
      found that the danger guard shipped that morning was BLIND to hotzones - warned level ran
      2.06x under what spawned, 2.75x at worst. ~~Original ask:~~ Owner picked "rich hunting
      grounds" and added: *"they should expire at some point or move around. Ideally players
      shouldn't be able to farm the same hotzone for real world days, maybe a few hours before
      they move."*
      So: keep the marker and the danger, add a REASON to enter (elite/rare spawns, better loot,
      faster XP), and give each zone a lifetime of a few hours after which it moves. Today they
      are a static 1.5-2.5x LEVEL bump - a thing players route around, which is why they stopped
      serving a purpose once regional menace covered "dangerous country".

- [x] **ART AUDIT — DONE.** Measured, not browsed: every tile composed on its real ground at the
      26px the map draws, compared pairwise. Four faults found and fixed (well/fountain were the
      SAME image; post_marker 4.4 from quest_board; blacksmith 13.0 from healer and the same job;
      pylon drew nothing at 0.8% ink). Nothing is closer than 22 now. Dungeon floors: no faults -
      the one that looked serious was my own tool not performing the game's composite.
      ~~Original:~~
      Same procedure as the gatherables: render everything on the background it really sits on,
      look, and bring alternatives back for the owner to choose between. Owner: *"For art show me
      alternatives for each and I can choose the better one."*

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

- [x] **GATHERING ECONOMY — MEASURED.** Common resources are fine (tree 19 tiles from a post,
  stone 25, ore 31). The damage was to BIOME-LOCKED types: a weight is a share of NODES when
  nodes roll per tile but a share of STANDS once each stand is one type, so `mountain_herb` came
  to ONE node in 48,521 tiles. Every fourth stand in a biome is now guaranteed to be its
  signature resource. ~~Original:~~
  Yield per tile WALKED falls with it. That is the intent, but the gathering JOBS have not been
  re-checked against it and may now be slow to level.
- [x] **DEATH RATE — MEASURED 2026-09-13, and it is worse than the old note suggested.** Two
  read-only audits agree. Written up in full at the END of this file; the fix is deliberately
  scheduled LAST (owner's call). ~~Original note:~~
  elsewhere. Two deaths at that sample size, so not yet a signal - but the chain steers by WIN
  rate and is structurally blind to deaths. Watch it in play.

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
a duplication, an unread buff name or a use that eats a stack; `tools/probe/equipment_audit.gd`
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
- [x] Assassinate read "~1 · 3% kill" in the Warden fight. The party payload hand-copied the engine
      fields and lacked 11 of them (finisher kind/damage, read_note, ramp, all three meter LABELS).
      Both paths now read `engine_display_fields`.
- [x] Wild Swing whiff read as "Meteor - 1 damage" with no miss line (13/60 casts). Now announced.
- [x] The card PREVIEW cast the upgrades: Opener and Sure Strike consumed at fight start, Sacrificial
      spent by the quote (every real cast 0), Wild Swing's quote flickering to 0. Preview is pure now.
- [x] Partial-cast damage pip quoted a full spend while the effect line quoted the planned one.

**Open, in the order they should be worked** (a blocker first, then the shared party-view cause, then
the teaching beats that depend on the Warden behaving):
- [x] **⛔ Warden's Watch III cannot be turned in.** FIXED on master, not released. Two causes: the
      Warden's hand-in loop lived in the KILL-progress path and step three is a DUNGEON_CLEAR; and the
      post's hand-in list compared "crossroads" with the runtime id "npc_crossroads" (third time that
      prefix has stranded a chain). `_warden_settle_steps` now runs for dungeon progress too, and
      every quest-vs-post comparison goes through `_same_post`. Probe: tutorial_walkthrough 9d.
- [x] **After the dungeon the player had no idea what to do.** FIXED on master, not released: the step
      now settles on the spot, he names and rings the nearest post, and the "Home" lesson fires the
      first time they are back inside one (quest log + Quest Board tile). He points; he does not
      auto-walk them home (possible follow-up).
- [x] **Party per-member state was a WHITELIST, and everything not on it was dropped between rounds.**
      FIXED on master, not released. Enumerated what every class's cards write onto a party view:
      `vanished` (Phantom Strike's crit never landed in party), `analyze_bonus`,
      `crit_escalation_stacks`, `casts_this_fight`, `forcefield_casts`, `guard_open`, and the
      runtime-named once-per-fight flags (`opener_used_<card>` ...). Now carried by default
      (`view_carry`), excluding only `_PARTY_VIEW_REBUILT_KEYS` and `_`-prefixed scratch.
      Also found: a non-lethal Assassinate aborted mid-cast in any party (script error reading the
      suppressed monster turn's missing `message`) - the suppressed turn now has the full shape.
      Probe: `tools/probe/party_view_carries_state.gd`, all 5 checks proven red on the old code.
- [x] **The Fighter's free opening stance never applied in party fights** (the solo start applied it
      inline). FIXED on master: `_apply_opening_stance`, called by both starts, players only. A
      party-only power change; the calibration chain measures solo, so it does not move the curve.
      `player_slow` / `slow_aura_applied` are set in the monster turn, not at start, and are carried
      per member now - nothing more to do there.
- [x] **Mark (and every skip-the-enemy-turn card) did nothing in any party fight.** FIXED on master,
      not released. Nothing on the party path read `skip_monster_turn`. The monster acts once per
      member per round, so a successful skip card now removes the action aimed at the member who
      played it (the exact solo equivalent), with a log line. Probe: party_view_carries_state s4.
- [x] **Enemy hits on the Warden popped their damage number over the ENEMY.** FIXED on master, not
      released - and it was every co-op TEAMMATE, not only the Warden. The client parsed "hits Warden
      Hollis for 43 damage" (no "you") as damage to the monster. The monster phase now sends measured
      `taken` / `monster_lost` on each beat and the client pops those. Probe: party_view_carries_state s5.
      Not verified in a running client - worth a look in the next co-op fight.
- [x] **No buff/debuff panel in party combat.** FIXED on master, not released. `player_status` /
      `monster_status` were solo-only; now `status_display_fields`, and the party payload builds from
      the member's REAL `_party_member_view` instead of a hand-made subset. Client feeds the strip from
      party messages. Not verified in a running client.
- [x] **The Warden's walk stepped into gathering nodes** and opened a gathering session, then waited on
      it forever (found as a 2-in-3 failure of tutorial_walkthrough 9a). A blocked escorted step is now
      a plain refusal - no bump interaction of any kind on the player's behalf.
- [→ carried forward to SMALL OPEN ITEMS] **Monster debuffs outside `_PARTY_SHARED_MONSTER_KEYS`** (`monster_charmed`, `monster_weakness`,
      `monster_slowed` + durations) are now carried PER MEMBER (before: dropped after the action). So a
      charm protects only its caster in co-op. Decide whether they should be shared - and if so, tick
      once per round, not once per member (see `_PARTY_DOT_KEYS`).
- [x] **Phantom Strike's card hid its damage, and its text promised a skipped turn.** FIXED on master,
      not released. `preview_ability_effect` now quotes it (probe: wild_swing_and_preview s2b, quoted
      296 / dealt 303); descriptions in client.gd (two), help, and constants.gd corrected off the cast.
- [x] **Exploit's description was stale** (said 15 + WITS/4, cap 35%; the cast is 10 + WITS/6, cap 22%). FIXED on master in all three client texts.
- [x] **The Warden was not drawn inside the starter dungeon.** FIXED on master, not released. The
      dungeon view had no code for him and the server sent nothing. dungeon_state now carries
      `escort: "warden"` (same gate as his guided dungeon fights) and the grid draws his floor-backed
      frame two steps back (behind a companion) or one (without), yielding to anything server-placed.
      Probe: dungeon_draw_order 1/1b. Not seen in a running client.
- [x] **After the starter dungeon his sprite sat NORTH of the player.** FIXED on master, not released.
      Step four had no goal, so the client placed him from a facing left over from the last DUNGEON
      step (leaving a dungeon puts you on the tile you entered from - no position change, so the
      facing never updated), and with a companion out the flank table puts him north for east/west.
      Now: step four's goal is the nearest post (`kind: "home"`, panel reads "sees you home to"), the
      facing resets on dungeon exit/complete, and clearing the dungeon rings the post and has him
      say where to go. He does NOT auto-walk home yet - the walk is still step three only.
- [x] **Safety net: the Warden cannot be walked into high country.** FIXED on master, not released.
      Owner chose the walk-in cap. While he escorts (stages 1-3, and stage 4 until inside a post), a
      step onto ground above `_warden_cap_level()` is refused with a panel in his voice. The cap is
      measured: highest Area Level within 40 tiles of the origin (the starter-dungeon ring) + 3 = 9
      on the local seed. Steps that do not climb always pass, so nobody is stranded.
      Probe: tutorial_walkthrough section 10. **Check the live seed gives a sane number too.**
- [x] **Teach what to do with spare gear back at the post.** In the "Home" lesson: Salvage (Inventory
      Q -> Salvage, anywhere) and Sell ($ tile -> List Item / Sell / Bulk List; paid on listing).
- [x] **Teach eggs and companions.** "An Egg" lesson when the Watch pays out its egg (hatches by
      walking, live steps-remaining, Eggs: line click = pause, Eggs button, and that a hatched
      companion must be CLICKED in Companions to come out). The first-hatch Companions panel now
      leads with deploying it and keeping it alive (walk/Rest heal; KO needs the H tile or a
      Revive Potion; the Inn heals only you). All controls read off the client, not remembered.
      None of the three has been seen in a running client yet.
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

- [x] **DONE v0.9.778 — restored on the `[url=]` mechanism.** **OPEN, and taken out by this fix: map hover and click-to-inspect for players and
      companions.** The overlay that was stood down also carried them. The mechanism to restore
      it already exists and is proven - the dungeon-entrance hover wraps a map cell in `[url=]`
      and the payload carries what it needs. Same shape, for `!other` cells and the figure that
      stands on them.

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

- [→] **Watch the five live characters at L3-L12** — moved to **THE BALANCE BATCH** (2026-09-18).
      Still worth saying here: at L25+ re-validate `make_char` against real saves; at L50+ the
      high-level balance work can finally be checked against real data.
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
- [→] **Feel check the rest change** — moved to **THE BALANCE BATCH** (2026-09-18).

## Phase 2 — balance follow-through (cheap audits, no chain)

- [→] **Sage / Barbarian / Ranger death per encounter** — moved to **THE BALANCE BATCH**
      (2026-09-18).
- [→] **The high-level win targets predate retreat** — moved to **THE BALANCE BATCH** (2026-09-18).
      Kept here because it explains the instrument: `refcal` REPORTS death rate but cannot steer by
      it — at a ~0.3% target there is under one expected death per sample, so there is no signal to
      correct against.
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

- [x] **DONE v0.9.776 — the minimap was the remaining cost, and it had a 7x in it after all.**
      6.9-7.6 ms a move -> 0.9 ms standing, 1.4 ms walking. Snapped sample lattice + a per-cell
      glyph memo keyed by WORLD coordinate (shared by every player, invalidated by
      `chunk_manager.tile_revision`), and markers scattered into their cells rather than all 861
      cells asking whether a marker is there. Was: the minimap is still
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
- [x] **THE 53-DUNGEON CARD CONTENT — DONE 2026-09-17. 53 of 53.** Owner, asked again what the
      49 dungeons without an exclusive card should offer: *"Write cards for all 53."* The blocker
      this entry named is gone: the cycle model shipped, so every new card is authored **with** its
      cycle value, the way the four originals were.

      **Four facts and a sentence each, and no new combat logic.** Every card uses an existing
      `kind` — the 19 arms of `_process_companion_card_ability`'s `match` are the whole vocabulary —
      so 49 cards cost 49 rows and nothing else.

      ⚑ **`tier` IS THE DUNGEON'S OWN `base_tier`, and that is the only tuning any of them needed.**
      Every kind scales its numbers off `tier`, so a card arrives sized to the place that drops it
      and nothing is hand-balanced per card. It is stored in the row because `dungeon_database.gd`
      sits on the other side of `drop_tables`' imports — so the probe asserts every row's tier
      equals its dungeon's `base_tier`, which is what keeps the copy honest.

      **What was deliberate rather than convenient:**
      * **Kinds are spread.** The widest is 4 of 53. A pass that reached for `strike` every time
        would have written 49 cards and one card, and the collection IS the reward.
      * **The strong control kinds are gated by where they can be earned.** `timestop` is the only
        kind that takes a monster's turn away outright, so it exists only at T7-T9 — Void Walker's
        Rift, the Time Weaver's Loom and Entropy's End — on top of its numbers already climbing
        with tier. The probe fails if one appears below T7.
      * **Each name comes from the dungeon's own boss and description**, not from its mechanic: a
        Rat King gives *Filthbite*, a Sphinx gives *Riddle's Answer*, an Ogre Chieftain gives *Bog
        Club*. A dungeon-exclusive card that named its mechanic would not be worth making
        exclusive.

      Probe: `tools/probe/dungeon_cards_complete.gd`. Its last section **casts all 53 through the
      real processor** and requires each to change something, because the four ways this pass could
      be silently wrong are all invisible: a dungeon with no card (falls back to the copy-drop), a
      typo'd `kind` (hits the `_:` fallback and deals plain strike damage while its face promises a
      poison), a tier that disagrees with its dungeon (a mis-sized card nothing complains about),
      and a `cycle` type the payout skips (a promise in the description that never pays). The kind
      and cycle lists are read **off the source of the functions that implement them** rather than
      restated in the probe.

      **Not covered, and stated so in the probe:** whether 53 cards read well together, or whether
      one is the obvious best pick at its tier. That is the sim's question and the owner's taste.

      **And every one of them has a FACE.** `companion_card_art_bbcode` returned art for
      `companion_card_` ids and "" for everything else, so a dungeon card has always drawn a blank
      art box — four blanks before this pass, and 53 after it, which would have made *no picture*
      the most common card face in the collection. A blank art box is the quietest kind of missing
      content: the card works, the layout is fine, nothing reports it.
      The image a dungeon card wants is not a new asset — it is the dungeon's own **boss species**,
      which `MonsterArt` already draws for every monster in the game. One lookup (card → dungeon →
      `boss_egg`), no art to make. Note the species and not the boss's NAME: "Goblin King" has no
      art, "Goblin" does, and the species is what the floors are full of anyway.
      The function is `card_art_bbcode` now and the old name **forwards** to it — one implementation
      under two names, because two implementations is how the two faces of one card drift apart.
      Probe: `tools/probe/dungeon_card_art.gd` — 106/106 cards draw something, companion art
      unchanged, and it checks the art is the right monster rather than merely non-empty.

      ⛑ **AND IT FOUND A FAULT IN THE ORIGINAL FOUR.** `bulwark_of_bone` was tier **3** and drops
      from `forgotten_crypt`, which is base_tier **1** — the only one of the four whose tier did not
      match its dungeon, which is the tell that it was a slip rather than a design. It made a
      starter-crypt card shield for attack x1.75 instead of x1.25 and overpriced it on the card
      market, since `calculate_card_valor` reads the same field. Corrected to 1. That is a small
      nerf to a card a player may already hold, and it is the honest cost of the row being wrong.

      ⛑ **Two instrument notes.** The probe first searched for `_process_companion_card_ability`;
      the function is `_process_companion_ability`, so its kind parser found **nothing** — and
      reported all 53 cards as naming an unimplemented kind. What it did not do is quietly pass:
      the `the kind list was read off the processor (0)` check failed first, which is the whole
      reason that check exists rather than trusting the list it builds. Separately,
      `get_root().add_child(sim)` has always errored in every probe that copies that shape, because
      `real_combat_sim.gd` extends SceneTree — harmless, since its `_init` builds what is needed,
      and dropped here.
      All four fault-detecting checks proven to fire by injecting a typo'd kind, a dungeon that does
      not exist and a mismatched tier.

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

- [x] **CHICKENS AS A DUNGEON FOOD SOURCE — DONE 2026-09-17.** Owner 2026-09-10: *"One argument
      for the chickens is they could be a food source that can be found in the dungeon so they can
      use it when they rest."* Asked on 2026-09-17 to choose between a floor-loot KIND, a creature
      you catch, and an interactive tile, the owner picked **a creature you catch** — so a chicken
      is an entity in `dungeon_monsters` with `is_critter`, not an entry in `_roll_floor_item`.

      **Why that choice is the better one mechanically:** a pickup is a tile you walk over, but a
      bird that runs is a small chase you have to decide whether to spend turns on while the
      wandering monsters close in — and turns are the dungeon's real currency. It flees at 65%
      when it sees you (**not 100%**: a critter that always steps away is uncatchable on open
      ground, and an uncatchable food source is worse than none), it never fights, and stepping
      onto it catches it for **1-3 Wild Fowl**, a tier-1 near-worthless `meat` material — a
      ration, not a trade good, or the food source becomes a valor farm.

      **Yield, stated in meals rather than probabilities:** 35% per floor, so a 3-floor run
      expects ~2 meals, a 5-floor ~3.5, a 9-floor ~6.3. A rest costs one food, so a deep run still
      cannot feed itself outright — the pressure is relieved, not removed.

      ⛑ **THE REAL WORK WAS NOT THE CHICKEN — IT WAS THAT "FOOD" HAD TWELVE OWNERS.**
      `["plant", "herb", "fungus", "fish"]` was written out **twelve times** across four files:
      the dungeon Rest handler, five market and order filters, two supply calculators, the
      client's food picker, the client's food counter, the market panel and a probe. Adding a
      `meat` type to eleven of them would have produced a bird you can sell but not eat, or eat
      but not sell, **and nothing would have failed loudly.** So
      `CraftingDatabase.FOOD_MATERIAL_TYPES` + `is_food_material()` is the one owner, all twelve
      copies now read it, and the probe is a token ban so a thirteenth cannot appear.

      **Three more faults found on the way, each the same shape:**
      * **"Remaining: N" counted the chicken.** The floor's only readout of whether it is done
        would have said a monster remained, and "Floor cleared!" could never have appeared while
        a bird was alive. The count loop was written out TWICE (floor renderer, side panel) — one
        `_dungeon_threat_counts()` helper now, skipping critters.
      * **The materials screen had a second list of types.** `display_order` drives the grouped
        display and had no `meat`, so Wild Fowl fell through to the unstyled "ungrouped" branch
        even though `type_info` had a name and colour for it. Added, *and* the ungrouped branch
        now reads `type_info` too, so a type that has styling can never render without it.
      * **An invisible ordering dependency.** `_spawn_all_dungeon_monsters` clears
        `dungeon_monsters[instance_id]` and only then calls the floor-item pass, which is where
        the birds spawn. Reorder those two and every bird in the game vanishes with **no error**,
        because clearing a dictionary is not a failure. Both sites are commented and the probe
        asserts the two line numbers stay in order.

      **Art:** `client/sprites/mobs_pack/ChickenA.png` (frames 0-2 are the walk cycle; 3-5 a
      second gait, 6-8 a peck — read off a contact sheet, since no check can tell you which nine
      frames are which). Baked floor-backed at 32px by a new
      `tools/bake_floor_backed.py --rebake-critters`, so it is reproducible output rather than
      irreplaceable art. The `_alert` twin is the same image deliberately — a chicken has no
      alert state, but a renderer that asks for one must never hit a missing file.

      Probe: `tools/probe/dungeon_critters.gd` — six sections, including driving the real spawner
      against real generated floors (12/12 placed, all on open tiles) and calling `load()` on all
      six baked tiles. Fault-injection proven: deleting the catch branch fails the ordering check.
      **What it does NOT prove** is that the bird is catchable in practice — that is arithmetic
      here (a 65% flee rate means the player closes a tile every ~2.9 turns on open ground) and
      wants one live run to confirm it feels like a chase rather than a chore.

- [x] **DONE — and DECIDED ON SCREEN, which is better than this entry proposed.**
      `client.gd::_dungeon_supports_floor` draws rock where the cell ABOVE is floor, so the rock
      sits UNDER the ground you walk on and a corridor reads as held up rather than outlined.
      `tools/probe/wall_samples.gd` renders three candidate rules on the SAME generated floor
      (rendering three different floors would have compared the floors) — 78 rock cells for the
      old all-sides rim against 37 and 42 for the two directional rules — and the owner picked
      from the pictures: *"The bottom one looks the best out of those."*
      Note the rule's recorded limit, which is an ASSET gap not a rule gap: *"unless we are
      planning to use something different to make the floors look supported from below."* A
      dedicated wall FACE below a floor edge would do this better, and none of the pool packs
      ship one. Was: **Walls only where they explain the space** (owner, 2026-09-10): *"It may be better if only
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

- [x] **DONE 2026-09-17 — ⚑ FULL UI / NAVIGATION AUDIT.** The map is a generated tool
      (`tools/ui_navigation_map.py`), every capability has a UI door, and the sweep ran twice:
      **119 chat commands → 72**. The map reports **0 arms are a surface's ONLY door** and
      **0 kept by hand**. What remains is 8 speech commands, 27 admin (kept by CLAUDE.md rule)
      and 17 argument-taking arms whose capability is reachable. Was:
      Owner 2026-09-17: *"At some point we need to go through every menu path in the game, assess
      what is still being used and what can be removed/retired, as well as ways to simplify them.
      We mentioned controller support or phone support at some point, that simplification will be
      crucial to that kind of support."*

      **Why it is placed here rather than later.** Mapping a maze to a D-pad is wasted work: every
      menu retired is one nobody has to map, and the phone item below already says in its own
      words that *"the three-panel desktop layout does not survive a phone screen"*. Doing input
      first means doing it twice.

      **The audit already has evidence, found incidentally on 2026-09-16/17 while merging the
      Atlas and the quest board — this is not a hypothetical tidy-up:**
      * **FOUR overlapping dungeon/quest surfaces**: the quest panel (a real card UI), the Atlas
        (text), the dungeon LIST (text), and the dungeon entrance screen. Two of them list
        dungeons with grade and level band.
      * **the dungeon LIST is already an orphan** — reachable only by typing `/dungeons`, no
        button anywhere in the game.
      * **119 chat commands** are whitelisted in `command_keywords`.

      **What it produces** (a map, before any deletion): every surface → its entry points → its
      one-line VERB. A surface with no entry point is dead. Two surfaces with the same verb are a
      merge. An entry point that reaches nothing is a dead button.

      **⚑ RETIRE THE `/commands`** — owner, same message: *"/commands should be retired as we no
      longer use those."* This is the explicit ask CLAUDE.md requires before touching them
      (*"Existing chat admin commands stay as fallbacks — don't migrate in a cleanup pass without
      explicit ask (muscle memory)"*), so it is authorised. But it belongs INSIDE this audit and
      not as a standalone sweep, for one measured reason: **`/dungeons` is currently the only route
      to the dungeon list.** Deleting commands before the audit gives each feature a button would
      silently remove features rather than remove navigation. Order: map → give every surviving
      feature a button → then retire the commands.

      ☑ **STEP ONE IS DONE — THE MAP EXISTS, AND IT IS GENERATED (2026-09-17).**
      `tools/ui_navigation_map.py` → `docs/design/ui_navigation_map.md`. A tool rather than a
      document, because a hand-written map of 28 panels, 119 commands and 380 action ids is stale
      the day after it is written, and the whole purpose is to decide what to DELETE — a decision
      that must not be made against a stale map. Re-run it after every deletion to prove the
      deletion did not orphan something else.

      **What it said on its FIRST run** (the figures the sweep was decided against — re-run the
      tool for today's; after two sweep rounds it reads **72 commands in 52 arms, 30 panels,
      382 action ids, 0 dead buttons, 0 only-doors, 0 kept by hand**):
      | | |
      |---|---|
      | chat commands whitelisted | 119, in 86 arms |
      | ...with no handler | **0** |
      | ...that are a surface's ONLY door | **0** |
      | panel scripts | 28 |
      | ...never opened from `client.gd` | **0** |
      | action-bar local ids | 380 |
      | ...with no case in `execute_local_action` | **1** |

      ⚑ **THE COMMAND SWEEP IS UNBLOCKED, AND THIS IS THE EVIDENCE.** The reason recorded above
      for not sweeping was that `/dungeons` was a feature's only door. It no longer is (it opens
      the Atlas tab since 2026-09-17), and **none of the other 85 arms is either** — every surface
      a chat command opens is reachable from somewhere else as well. So retiring the commands now
      removes navigation and not features, which is precisely the condition this entry set.

      **The one real dead end it found — and it is FIXED (2026-09-17).** The action bar's **Build**
      button. And it is worse than the count suggests, because of WHICH button it is: slot 4, the
      **contextual location action** CLAUDE.md names as the game's primary entry point for
      whatever you are standing on. Stand inside your own enclosure and that slot reads *Build*;
      pressing R did nothing and clicking it did nothing. Both paths come through
      `execute_local_action` (`trigger_action` dispatches click and hotkey alike) and it had no
      case for `build_shortcut` — nor for any other `*_shortcut` id. CLAUDE.md pitfall #11 exactly.
      It survived because the same id works perfectly from the shortcut ROW: the feature was
      reachable, so nobody ever found the dead door. Fixed by FORWARDING to
      `_on_shortcut_button_pressed("build_shortcut")` rather than copying its nine lines of
      mode-clearing — a second copy of *how to enter build mode* is where the next mode added to
      that list would go missing. The map now reports **0 of 380**, and the check is proven to
      fire by removing the case again.

      ⛑ **THE TOOL FLAGGED 34 LIVE FEATURES BEFORE I CHECKED ITS OUTPUT**, and every fault
      pointed the same way — toward deleting something that works. In a tool whose product is a
      deletion list that is not an inaccuracy, it is a proposal:
      * **11 "dead" action ids were handled.** `help_quest_log` and nine siblings share ONE match
        arm spread over four lines with `\` continuations; the parser matched an arm only when it
        fitted on one line. `job_commit_` is not an id at all — it is a prefix.
      * **23 "untypable" commands were sub-commands** — `accept`, `invite`, `deposit` are arms of
        NESTED matches (`/clan invite`, `/vault deposit`). Fixed by judging an arm by its
        indentation depth.
      * **2 "never opened" panels** were opened by verbs my whitelist did not contain
        (`show_with_payload`, `open_combat`). A whitelist of opener verbs cannot be complete.
      * **the verb column printed method names** — and after two rounds of blaming the docstring
        parser, the cause was the opener loop below it reusing the variable `verb`. Shadowed in
        plain sight, eight lines under the code I kept editing.

      ⛑ **And the first attempt to prove the only-door detector FIRES was itself invalid.** I
      injected a fake surface call next to `show_help()` — and hit line 16239, inside
      `execute_local_action`, not the one at 29572 inside `process_command`. The test never touched
      the code under test and reported nothing, which looks exactly like a detector finding nothing
      wrong. Re-injected at the right line, it flags correctly. **A "0 found" result is worth
      nothing until the injection lands in the function being tested.**

      ☑ **STEP TWO IS ALSO ANSWERED (2026-09-17): nothing needs a button first.** The map now
      classifies all 86 arms, and the retirement list is four groups rather than one number:

      | group | count | why it is its own group |
      |---|---|---|
      | **speech** | 8 arms | `/whisper`, `/reply`, `/partychat`, `/afk`… A chat line IS the right interface for talking. Retiring them because they start with a slash would delete the ability to whisper. |
      | **admin** | 32 arms | CLAUDE.md: *"don't migrate in a cleanup pass without explicit ask (muscle memory)"* — and *"we no longer use those"* is the opposite of true for the owner's own tools. Grouped from the whitelist's own line layout, not judged by name. |
      | **takes an argument** | 10 arms | `/block bob`, `/watch bob`, `/trade bob`. *Open the screen* and *do this to THAT name* are different capabilities and only the first was checked. |
      | **safe to retire** | 36 arms | Their surface is reached from a non-command path, or they open no surface at all. |

      ⛑ **Three times the list had to be narrowed, and each time it was about to delete something
      that works.** *"Reachable from somewhere else"* counted ANOTHER COMMAND as somewhere else, so
      two commands opening the same screen both read as safe; the first list swept the admin tools
      by implication; and the second swept the parameterised actions. Each narrowing came from
      reading the list rather than from a failing check — which is the argument for bringing a
      generated list to the owner as GROUPS to approve, not as a number to act on.

      ☑ **AND THE ANSWER TO “whether the 10 argument-takers have a UI” IS: BUILD ONE.** Owner
      2026-09-17: *“Anything that remains needs a way to access it via the UI. Example, on the
      player list you right click a player for a menu that has a whisper option, etc.”* That turns
      the retirement question inside out — the list is not *which commands can go*, it is *which
      capabilities still lack a UI route*.
      **Built: a player context menu** (`PopupMenu`, so a D-pad can walk it — the whole reason for
      this audit is controller and phone) offering **Whisper, Inspect, Trade, Duel, Watch, Add
      Friend, Block**. That is 7 of the 10 argument-takers and most of the speech group in one
      surface.
      ⚑ **IT SENDS NOTHING OF ITS OWN.** Every action forwards to the same function the chat
      command calls — `player_examine`, `player_block`, `player_friend_add`, `player_duel`,
      `player_whisper`, plus the two that already had one. Those were one-line `send_to_server`
      calls inside command arms; a menu written the obvious way would have carried a second copy
      of every protocol message, and the day one gained a field only one copy would get it.
      ⚑ **TWO DOORS.** Right-click on the online list, as the owner described — and an **Actions
      button** on the player-info popup, because a right-click survives neither a controller nor a
      touchscreen and CLAUDE.md already says a button is discoverable where a hotkey is not.
      ⚑ **Whisper needs WORDS, so it is not one click.** It sets a target, the input says who it is
      talking to, the next line goes privately, and Escape or an empty line cancels. One line is
      ONE whisper — staying in the mode is how the next idle thought goes privately to somebody it
      was not meant for. Same idiom as `bug_report_mode`, not a new mechanism.
      Probe: `tools/probe/player_actions_menu.gd`, on the real client scene — a `PopupMenu` whose
      `id_pressed` is unconnected looks exactly like one that works, so the signal is emitted for
      real and the effect watched.
      ⛑ **A patch script lost its edit to a later assertion and reported success**, so the whisper
      send path was simply absent; the probe caught it as two failures while the patch had printed
      *ok*. Second time today. **A patch asserts what it needs FIRST, or writes immediately after
      each edit** — these scripts do all their work in memory and write at the end, so anything
      that throws in between discards good edits silently.

      ☑ **AND THE LAST THREE ARE ROUTED (2026-09-17). Every capability now has a UI door.**
      * **`/topics` + `/topic <key>`** → a **topic INDEX** in the help panel, reached by a
        **Topics** button beside Help and by an *← All topics* button from any topic. Those two
        commands were discovery and navigation for the whole help system: 36 per-screen topics,
        and the panel could show one but never list them — so every screen's `? Help` button was
        a dead end. The rows are Buttons rather than clickable BBCode, for the same reason the
        player menu is a PopupMenu: only a Button takes focus.
      * **`/mentor on|off`** → **settings slot 7**, which fell vacant the same day when the
        overworld sprite toggle was retired. It was the only persistent preference in the game
        that could be set only by typing.
      * **`/donate <amount>`** → a **Donate button on the Titles screen**, where the pilgrimage
        already lists the Trial of Wealth and then told you to type a command. Like Whisper it
        needs a value, so the button asks and the next line answers; a bad amount or an empty line
        ends the prompt rather than spending.

      ⛑ **The mentor row needed the server's level gate, so the client now carries a COPY of a
      server constant** — worth it, because the row greys itself out instead of letting a player
      press a key and be refused, but only while the two agree. The probe compares them and is
      proven to fire by drifting the client's to 25.

      ☑ **FIVE ADMIN COMMANDS RETIRED (2026-09-17).** Owner: *“Retire the ones the panel
      covers.”* Checked one at a time rather than by name — `/godmode`, `/giveall`, `/heal`,
      `/resetquests`, `/spawnwish` each take no argument and send exactly the message an `/admin`
      button already sends, verified against `admin_panel.gd`.
      **The near-misses deliberately stayed.** `/giveitem <tier>`, `/spawnmonster <name>`,
      `/givecompanion <type>`, `/giveegg <type>` all LOOK covered — the panel has `give_item_t5`,
      `spawn_mob_elite`, `give_companion_t5`, `give_egg` — but those are fixed variants of a
      parameterised command, and a button that gives a tier-5 item does not replace one that gives
      any tier. `/admin` stays: it is the door to the panel.

      ⛑ **THE NAVIGATION SWEEP IS NOT SAFE YET, AND THE LIST NARROWED TWICE MORE — ONCE AFTER THE
      OWNER SAID YES.**
      * **The argument detector recognised one spelling.** It looked for `parts[` and missed
        TWELVE arms that read their words as `text.split(" ", false, 1)` — `/duel <player>
        [stakes]`, `/spendstat`, `/settitle`, `/vault`, `/buystone`, `/clandesc`, `/clanmotto`,
        `/clancolor`, `/clanpost`, `/bounty post`. Every one was sitting in the approved list.
        **36 arms → 25.** A list produced by an incomplete detector does not become correct by
        being approved.
      * **“Opens no surface” was read as “safe”, and it is not the same thing.** Five of the
        remaining 25 send a message or print a line rather than opening a screen — and the owner's
        rule is that the CAPABILITY needs a UI route, not that the command opens one.
        `/unwatch` is fine (Escape already stops watching), but **`/bug` and `/report` have no
        button at all** — `generate_bug_report` is reachable only by typing, which is the worst
        possible thing to be command-only.
      * **And the friends/block system has no panel whatsoever.** There is no `*_panel.gd` for it.
        The context menu added *Add Friend* and *Block*, but **seeing your friend list, seeing and
        answering friend requests, and seeing or clearing your block list** exist only as
        `/friends`, `/freq`, `/blocklist`, `/unblock`. Retiring those removes the only way to
        accept a friend request.

      ☑ **BOTH BUILT 2026-09-17. The sweep is unblocked.**
      * **A Report button beside Send**, on every screen. `_on_bug_button_pressed()` had existed,
        complete and correct, **connected to nothing** — a handler for a button nobody built — so
        `/bug` was the only way to report one. That is the worst thing in the game to be
        command-only: a player who has just hit a bug is exactly the one who does not know the
        command.
      * **A People panel** (`client/social_panel.gd`): Friends / Requests / Blocked, with the
        pending count on the tab so an unanswered request is visible without opening it. The whole
        friend system had no surface — no `*_panel.gd` at all — and `/friend accept <name>` was
        the ONLY way to answer a request, with `/freq` the only way to learn one existed. A request
        you cannot see is a request you cannot accept.
        It sends **no protocol message of its own**: every action forwards to the function the chat
        command calls, and the four answers (`accept` / `reject` / `cancel` / `remove`) got a shared
        `player_friend_answer` rather than being inlined twice. Nothing was added to the protocol —
        the server already sent all three lists.

      ⚑ **AND THE MAP LOOKS BOTH WAYS NOW.** It could only find entry points that reach nothing;
      the bug button was the opposite — a destination nothing reaches, which from the source looks
      exactly like a working feature. `orphan_handlers` closes that class. It reports **1**:
      `_on_move_button`, which is dead code rather than a missing door (a movement pad that no
      longer exists), kept deliberately as the starting point for the touch controls the phone item
      will need. The tool cannot tell the two apart and says so.

      ☑ **AND THE SWEEP RAN: 119 chat commands → 90.** 24 navigation names (16 arms) plus the 5
      admin ones. Every retired arm was checked BY HAND against a named route — Help button, Pouch
      / Post / Stones / Stats / Clan / Quests / Atlas shortcuts, the post panel's own Feed All
      button, the contextual [R] slot for Craft and Fish, the throne tile for Titles, Escape for
      unwatch, and the three surfaces built today (Topics, People, Report).

      ⛑ **THE LIST NARROWED FIVE TIMES, from 78 “safe” to 16 — and every correction moved the
      same way, toward deleting something that works.** Worth keeping as one list, because they
      are all the same mistake at different depths:
      1. *“Reachable from somewhere else” counted another COMMAND as somewhere else.*
      2. *The admin tools were swept by implication* — CLAUDE.md says they stay without an
         explicit ask.
      3. *The argument detector knew one spelling* (`parts[`), then a second (`text.split`), then
         a fourth (`parts.slice`) — `/search <term>` reached the approved list that way, and there
         is no search box anywhere.
      4. *“Opens no surface” was read as “safe”*, when the owner's rule is that the CAPABILITY
         needs a route.
      5. **`display_game` was being counted as a surface.** It prints a line of text. So every arm
         that printed its answer read as *opening a screen*, and “a button opens that too” was
         trivially true because everything in the client calls `display_game`. **That single
         mistake is most of the difference between 78 and 16.**

      **Seven arms were recorded as KEPT** because a hand check found no route at all — `/clear`,
      `/crucible`, `/clanposts`, `/mentors`, `/debughatch`, `/catches`+`/deck`,
      `/bountyboard`+`/bb`. Unrecorded, the next reading of the map deletes seven working features.

      ☑ **AND THEN THEY ALL GOT A DOOR (2026-09-17) — `KEEP_NO_ROUTE` IS EMPTY.** Owner:
      *"all slash commands should be accessible through a UI element that makes sense. If we don't
      have a place for it we need to build one in a tree structure that makes sense and doesn't
      crowd our UI or cause confusion."*

      `client/menu_tree_panel.gd` — **30 entries in 7 categories** (Character, World, People,
      Clan, Your Post, Help, Settings), categories on the left, entries with one-line hints on the
      right, every row a focusable `Button` so a D-pad reaches it. The hint follows FOCUS as well
      as hover, or a controller player gets a menu of bare verbs.

      ⛑ **IT COSTS THE SHORTCUT ROW ONE BUTTON.** The row already carried fifteen, which is
      the crowding the owner named; thirteen homeless capabilities could not go there. A category
      list is two clicks to anything and adding the next capability costs a table row rather than
      a sixteenth button. **Nothing existing moved** — every shortcut and panel is still where
      players know it; this is an additional door, not a reorganisation.

      ⛑ **THE TREE DISPATCHES NOTHING ITSELF.** Every entry is an id one of the two existing
      dispatchers already handles (`execute_local_action`, `_on_shortcut_button_pressed`), so a
      tree entry cannot behave differently from the button that does the same thing.
      `tools/probe/menu_tree_routes.gd` calls `MenuTreePanel.all_action_ids()` and reads the two
      match statements from source — two independent sources, not the circular check that bit
      the direction table — and fails on an id nothing handles or a row that appears twice.
      **Both fault shapes were injected and both went red.**

      ⛑ **ONE PROMPT, NOT FIVE MORE BOOLEANS.** Four clan setters and help-search all need a
      typed line, and the client already had THREE bespoke ways to ask for one —
      `bug_report_mode`, `whisper_target`, `pending_donate` — each with its own `send_input`
      branch, ESC arm and placeholder handling. Five more would have made eight copies of one idea.
      `TEXT_PROMPTS` + `_prompt_action` is one branch, one cancel, one placeholder. (The
      "one value, many owners" shape again, caught before it landed rather than after.)

      ⛑ **AND `/debughatch` HAD NO ADMIN GATE.** Found while moving it into the /admin panel:
      `handle_debug_hatch` grants a **random companion** and opened with `characters.has(peer_id)`
      — which only asks whether you are logged in — where every other `gm_*` handler opens
      with `_is_admin` + `_gm_deny`. Any player could type `/debughatch` for a free companion, as
      often as they liked, and the command was in the client's own whitelist so it was not even
      obscure. Now gated, renamed `gm_debug_hatch`, and a button on /admin › Companions.

      ⛑ **THE CONTEXT MENU COULD ONLY DUEL FOR NOTHING.** `player_duel(target, stakes)` takes
      `"none"` or `"valor_10"` and the menu hardcoded `"none"`, so the wagered duel — the
      half anyone would want — was still typed-only, and a sweep reading "Duel is in the menu"
      would have called the capability covered. Second row: **Duel for Valor**.

      ☑ **SWEEP ROUND TWO: 90 → 72 commands.** 18 names in 13 arms, each named against the
      route that now serves it: `/clear`, `/crucible`, `/clanposts`, `/mentors`, `/catches`+`/deck`,
      `/bountyboard`+`/bb`, `/trades`+`/tradehistory`, `/search`+`/find`, `/clandesc`,
      `/clanmotto`, `/clancolor`, `/vault`+`/clanvault` (the Clan panel's own Vault button —
      read in `_on_clan_panel_vault`, not inferred), `/debughatch`.
      **NOT retired:** `/clanpost` and `/companion` — both take subcommands and both have only
      partial panel coverage. The list has narrowed five times already; two arms are not worth a
      sixth.

      **The map now reports `0 arms are a surface's ONLY door` and `0 kept by hand`.** What remains
      is 8 speech commands, 27 admin (kept by CLAUDE.md rule), and 17 argument-taking arms whose
      capability is reachable but whose exact syntax is not worth a button.

      ⛑ **AND THE PHOTOGRAPH FOUND TWO BUGS THE PROBE COULD NOT.** The tree parsed, opened,
      and printed `visible=true entries=30`. The capture said it was in the wrong place:

      1. **Both overlay panels were pinned TOP-LEFT and the dim covered nothing.** `top_level =
         true` DETACHES a Control from its parent's rect, so `PRESET_FULL_RECT` has no rectangle
         to resolve against, sizes the panel to zero, and the CenterContainer centres inside a
         zero-size box — landing it at the origin with the full-screen dim shrunk to the
         panel's own bounds, leaving the game fully lit and fully clickable behind a modal.
         `social_panel.gd` has carried this since it was written and was **never photographed**.
         Both now size themselves from the viewport and re-fit on window resize.
      2. **A full-screen panel did not stop the action bar.** It polls
         `Input.is_physical_key_pressed()`, which does not care what has focus — so `1` browsed
         the menu AND fired action slot 5 behind it. CLAUDE.md's golden rule, reached from a new
         direction. `any_popup_open` was a hand-maintained OR of **seven booleans**, which is
         exactly why a panel written the day before was not in it; an eighth would have been the
         same mistake. It now ASKS: `_blocking_overlay_open()` returns true for any visible child
         with a `blocks_hotkeys()` saying so. A panel opts in with two lines, and the overlays
         that must NOT eat the bar — combat scene, tutorial hint — simply do not.

      The selected category was also marked with `disabled`, which made the thing you were looking
      at the dimmest item on the panel. Colour and a ▸ marker instead.

      ⛑ **A SWEEP IS NOT DONE WHEN THE ARM IS DELETED — it is done when nothing still tells
      the player to type it.** Thirteen help lines named retired commands, and **four had been dead
      longer than today**: the `Cmds:` line taught `/inventory`, `/abilities`, `/help` and
      `/clear`, and the line shown to a brand-new player who skips the tutorial said *"Type /help
      for a quick reference."* A help page confidently naming commands that do nothing is worse
      than no help page — the player concludes the game is broken rather than the text is stale.
      All thirteen now name the button. **Add this to the retirement checklist: grep the help text
      and the player-facing strings for every name you delete.**

      Probe: `tools/probe/social_and_bug_routes.gd`, on the real client scene, proven to fire by
      disconnecting the bug button again (3 checks go red).
      ⛑ Its Accept check failed first on MY OWN lambda: a GDScript closure captures by VALUE, so
      assigning to a captured variable inside it rebinds the lambda's copy and the outer one never
      changes. The signal was firing correctly and the probe could not see it. Mutate the
      dictionary, never reassign it. Plus the judgements the tool
      says it cannot make — whether two surfaces with different verbs are the same thing to a
      PLAYER, and whether a button's MODE is ever entered. Those need the game run.

- [ ] **THE VALOR ECONOMY, REALM-WIDE — owner direction 2026-09-17.** Asked to pick a target
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

- [x] **MOSTLY DONE 2026-09-17 — controller support, slices 1 and 2.**

      ⚑ **MEASURED FIRST, AND THE MEASUREMENT IS THE WHOLE STORY.** The engine ships **91
      default actions and only SIX carry any joypad binding**. `ui_up/down/left/right` have the
      D-pad AND the left stick, so focus navigation between Buttons already worked - which is why
      the audit made every new panel row a real `Button`. But **`ui_accept` and `ui_cancel` have
      no pad event at all**, so a pad could move the highlight over every screen in the game and
      never press anything. Two events was the difference between unusable and usable, and no
      amount of UI work would have found it - it is in the engine's defaults, not in this codebase.

      Set from CODE, like `vsync_mode` and `max_fps`, because the editor strips project.godot
      settings it considers default on every `--editor --quit`. `--buildverify` reports them and
      the release gate asserts them.

      ⛑ **AND THE GATE CAUGHT AN ORDERING BUG ON ITS FIRST RUN** - `--buildverify` prints and
      quits at the top of `_ready`, and the binding call sat 160 lines below it, so it reported
      `ui_accept=0` in a build that had them. The probe missed it because it waits eight frames.
      **Anything `--buildverify` reports must be established ABOVE the `--buildverify` block.**

      Mapping: D-pad/stick move (reusing `_arrow_mask_to_dir`, the ONE direction table - writing a
      second one is what made the client's directions wrong in every entry last time); A/X/Y/LB/RB
      are action slots 0-4; B backs out; left-stick click hunts; **Back** focuses the action bar
      (all ten buttons are already `FOCUS_ALL`, measured 10/10, so that is the whole feature for
      slots 5-9); **Start** opens the Menu tree, which is the pad's guaranteed door because the
      shortcut row is deliberately `FOCUS_NONE`.

      Probe: `tools/probe/controller_bindings.gd` injects a real pad event rather than re-reading
      what the code wrote, and records the engine default that motivated the work. Proven to fire.

- [ ] **⛑ CONTROLLER: NOT ONE KEY HAS BEEN PRESSED ON A REAL PAD.** `Input.get_connected_joypads()`
      was **empty** for every measurement above. Everything is verified by injected events and by
      reading the InputMap, which proves the WIRING and says nothing about the FEEL: whether the
      move cooldown suits a held stick, whether the deadzone is right, whether Back-to-focus-the-bar
      is discoverable, or whether a diagonal is comfortable. That needs a pad in a hand.
      Was: Godot has joypad input built in; a D-pad or stick gives all
      eight directions natively and the face buttons map to the action bar. Scope it as its own
      piece. Note `_on_move_button` already exists as an orphaned 8-way handler with no caller —
      an on-screen pad that was built and removed — and it is the natural target for both a
      controller cursor and touch.

- [ ] **Phone / touch (LATER, its own arc).** Needs a mobile export preset, a touch UI, and a
      layout rework — the three-panel desktop layout does not survive a phone screen. Much larger
      than the other two; do not start it inside another arc.

## Phase 3 — combat UX debt (visible to every player, every fight)

- [x] **DONE v0.9.773 — all three, and two of them were one cause as predicted.** Nothing owned
      the tooltip's lifetime: `_wire_hover(rtl)` now connects hover-in and hover-out as a pair
      across all 8 surfaces (0 hand-wired connections remain), the panel watches its own
      `visibility_changed` and closes the popup, placement reads the mouse in the POPUP's
      coordinate space after a layout frame, and APEX/ELITE are wrapped as hoverable terms.
      Probe: `tools/probe/hover_lifetime.gd`. Was: **HOVER TOOLTIPS: three faults, reported live 2026-09-11 by the owner.** All three are the
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
- [x] **Two stale instruments — BOTH CLOSED.** (1) DONE 2026-09-15: `card_vs_server.gd` replaced
      by `card_face_truth.gd` and deleted.
      (2) **DONE 2026-09-18.** `card_upgrade_effects.gd` reported **23 upgrades "NOT YET WIRED"**
      off a hand-typed array that had gone stale - and the number was not merely out of date, it
      was **entirely false**: measured against the code, all **56 of 56** upgrades in the pool are
      read by combat code. `bulwark` is consumed at `combat_manager.gd:7785` and the
      Executioner family at `:8084`, neither of which appeared in the hand list.
      The list is now DERIVED: an upgrade is consumed by its quoted id, so the section searches the
      four files that could consume one and excludes the table that DEFINES them (a definition is
      not a use, and counting it would mark everything wired forever).
      **It also FAILS now instead of printing a note** - an upgrade offered to a player that does
      nothing is the exact defect the redesign exists to remove, so it is not a remark.
      **Proven to fire** by injecting an inert upgrade into the pool: `pool 57 / read 56 / READ BY
      NOTHING 1`, named and failed. Restored and green.
      ⛑ The two claims are deliberately kept apart in the output: *"the code reads this id"* is
      not *"this upgrade measurably does something"*. The damage table above it proves ten of them;
      this section can only find the ones nothing reads at all, which is a floor, not a verdict.
- [x] **Knight +15% damage and Mentee +50% XP — WIRED 2026-09-18.** Both were promised in the
      title UI, the help page and `titles.gd`, and all three getters had **no callers** - a player
      knighted by the High King got a blue prefix and nothing else.
      **Wired rather than deleted, and the sibling is why.** `get_knight_market_bonus` is called at
      six sites in server.gd; the damage half of the same status, defined eight lines below it in
      the same file, was called nowhere. Nobody implements half a title on purpose, so this reads
      as an oversight, not a design decision - and deleting would take something from players who
      earned a rare title.
      **One judgment call, stated because it is arguable:** Mentee is applied OUTSIDE the 1.50x
      XP cap. That cap exists to stop race x class x Sanctuary snowballing (audit #2); a Human
      Ranger with a maxed Sanctuary is already at 1.50, so folding Mentee in would make the grant
      do nothing for exactly the accounts most likely to hold it - wired and still dead, which is
      the fault being fixed. Reverse it if that reads wrong.
      Probe: `tools/probe/title_bonuses_reach_the_dice.gd`, which EXECUTES rather than greps -
      every one of these functions existed and returned the right number, so reading the source
      proved nothing. Measured 1,100 vs 1,650 XP on two otherwise identical characters.
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
- [x] **Buff panel, party half — DONE 2026-09-18.** A teammate's card carried name, an HP bar and
      a resource bar, so in a party you could watch an ally dying with no way to see WHY - no
      poison, no blind, no shield, no mitigation. The member payload simply did not carry the
      fields; the player has had that strip since solo combat.
      Sent through `status_display_fields`, the SAME builder the player's own strip uses, whose
      docstring already said the party payload should hand it the member's real view. That matters:
      this strip went missing from party fights once before (2026-09-15) precisely because only the
      solo state carried the fields, and a second per-member builder is how they would drift again.
      **Stacking: grouped, not de-duplicated.** The same buff applied twice used to draw two
      identical chips, which reads as a rendering glitch - and on a member card, a third the width,
      it pushes the rest off the row. It is one chip with `×N` now, keeping the entry with the
      LONGEST remaining duration, because that is the one that answers "how long do I have this".
      Dropping the repeat instead would have hidden real information: a doubled buff is worth
      roughly twice as much and there is no other way to know it landed.
      Probe: `tools/probe/party_buff_strip.gd` - executes the chip builder and asserts one chip,
      the ×2 mark, the longer duration, and a single-buff control that must carry no count.
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
- [x] **Death replay / shareable combat log — THE LINK IS DONE 2026-09-18.** Nearly all of this
      was already built, which is the point: every death has carried its full `combat_log` inside
      `death_data` since the leaderboard was written, the server already answers
      `get_leaderboard_death` with it, and the client already renders it. The only missing piece
      was a way to ASK - you had to open the leaderboard and find the row. The death announcement
      now carries **⚑ see the fight**, and it goes to every peer including players sitting on
      character select.
      **Chat links were not clickable at all** before this: nothing was ever connected to
      `chat_output.meta_clicked`, so a `[url]` written into chat rendered as underlined text that
      did nothing - worse than no link, because it advertises an action and then refuses it. It
      routes through the same dispatcher as `game_output` so a meta means one thing wherever it is
      written.
      **A correctness fix came with it:** the link names a death by NAME (`add_to_leaderboard`
      stamps `died_at` internally and hands back only a rank), so "no timestamp" had to be taught
      to mean the most RECENT death under that name. It used to mean "whichever matched first", and
      `entries` is sorted by LEVEL - so a name that had died twice returned whichever ranked higher.
      Probe: `tools/probe/death_log_link.gd`, which walks the route rather than the parts.
      **✅ AND THE REPLAY — DONE 2026-09-18.** Click the link and the fight plays back **at the
      pace it happened**, one line at a time, with pause / restart / skip-to-end and a progress
      bar, headed by who died, at what level, to what, and over how many rounds. Speed comes from
      the viewer's own combat-speed setting rather than a second preference to discover.
      **✅ AND IT PLAYS OUT AS THE FIGHT — 2026-09-18, second pass.** Owner: *"it should play out
      like the fight does. Ideally it's a windowed replay of the fight from the dead players
      perspective."* It runs in the **real combat panel** now: their battler, their gear, their
      companion, the monster that killed them, and BOTH health bars moving on the beats the fight
      actually had, at the viewer's own combat speed.
      **⛑ THE BLOCKER WAS THE STORED DATA, NOT THE IDEA — so the data changed.** `combat_log` is
      flat BBCode strings (checked against a real 190-line record on live), and everything a replay
      needs to drive bars exists only at the instant an action resolves. Rather than read numbers
      back out of the prose - the mistake that put co-op damage numbers on the wrong combatant -
      the server now RECORDS them: `combat_replay`, parallel to `combat_log`, one beat per line
      carrying actor / dealt / taken / monster HP / player HP. The metadata was already computed
      and already sent to the live client; this keeps a copy. Recorded at BOTH log-append sites,
      so an item-use turn does not leave a hole mid-replay.
      **Deaths recorded before this have no track and fall back to paced text.** They are not
      re-animatable and no amount of guessing makes them so.
      **Two traps caught while building, both about owning the screen:** a FINISHED replay still
      holds the input (otherwise its own "press Space to close" falls through to Rest and starts a
      real fight underneath somebody else's death, with the panel pinned over it); and a fight
      starting mid-replay ends the replay rather than sharing the log with it.
      Probes: `death_scene_replay.gd` asserts the recorded track reproduces the HP CURVE down to
      zero - a track that exists but never kills anyone would render a death in which nobody dies,
      with every field present and correct - and `death_replay.gd` still covers the text fallback.
      Probe `tools/probe/death_replay.gd` DRIVES the playback rather than reading the source - a
      replay that renders nothing and one that works look identical from outside - and covers the
      shared-panel trap: a ticking replay must stop when someone opens an ordinary log in the same
      panel, or it appends into it from underneath.
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

- [x] **DONE 2026-09-17 — Extend UI-scale registration.** Action bar, status panel, and the four big panels.
      Both are now click-to-resize (`ui_scale_manager.register`), which was the same three lines
      `world_map` has used since v0.9.647: register the control, have the applier call
      `_on_window_resized()`, and read the per-element scale INSIDE the font maths.
      ⛑ **The per-element factor MULTIPLIES the settings slider, it does not replace it.** The
      slider owns the bulk factor, the overlay owns the per-element one, and the font is their
      product. Writing the overlay's value back into `ui_scale_buttons` would have been simpler
      and wrong — the settings menu would then display a number the player never typed.
      Probe: `tools/probe/ui_scale_registration.gd`, on the real client scene at 1920x1080,
      because both ways this fails silently are invisible in the source: a registration whose
      apply path never reads `get_scale` (present, reachable, does nothing) and a per-element
      value that clobbers the slider.
      **Two instrument faults found writing that probe, both worth recording:**
      * It read the baseline straight after `instantiate()`, before the client had scaled itself —
        so the baseline was whatever the scene file carried, disagreed with the settled value
        (29px vs 44px) and **failed a different check on each run**. One explicit resize pass
        before measuring fixed it; both runs now agree exactly.
      * Its composition check ran at slider 2.0x, where the font is already pinned at
        `BUTTON_MAX_FONT_SIZE` — so adding a 1.5x per-element factor changed nothing and the check
        passed on `>=` while proving nothing. **A cell where the clamp is binding cannot tell
        composition from replacement.** Moved to 0.6x (17px → 26px).
      **And a real measurement worth keeping:** at 1080p the status panel's font is **10px at
      1.0x**, one point off its floor of 9. So its slider's useful direction is UP, which is the
      owner's own 2026-09-15 decision (*"The status panel text can be smaller by default"*)
      meeting a readability floor — not a fault. The probe pins that, so a drift back upward shows.
      ☑ **AND THE OTHER FOUR ARE DONE 2026-09-17 — with ONE walker, not four appliers.** The
      note above guessed each would need a bespoke applier. Measured instead: all four set their
      fonts with `add_theme_font_size_override` and **not one uses an inline `[font_size=]` BBCode
      tag**, which is the only case a walker cannot reach. So `UIScaleManager.scale_fonts_under`
      covers every one of them without a single hand-edit.

      ⛑ **NOT the whole-panel `scale` trick the combat player card uses.** That precedent sits
      three functions away and is wrong here: all four roots are `PRESET_FULL_RECT`, so they
      already fill the screen and scaling one up pushes its own content off the edges. What a
      player wants from these is bigger TEXT, not a bigger box.

      ⛑ **THE BASE SIZE IS CACHED ON THE NODE, NOT IN A TABLE.** The market rebuilds its rows
      on every refresh, so a dictionary keyed by Control would accumulate dead entries while each
      new row scaled from an already-scaled value and ran away within a few refreshes. A meta
      travels with the node and dies with it.

      ⛑ **AND THE SOURCE COUNT UNDERSTATED THE WORK BY 77%.** Grepping the four files found
      **86** overrides; at runtime the walker touches **152** (67 / 42 / 26 / 17), because panels
      build repeated rows. Counting source lines is not counting the thing.

      ⛑ **`get_theme_font_size_override()` DOES NOT EXIST in Godot 4** — I invented it. The
      error repeated once per Control until the probe run hung with no verdict, which is the
      documented "a probe that fails to parse never exits" shape wearing a different hat.
      `has_theme_font_size_override` is real; reading the value is plain `get_theme_font_size`.

      Probe: `tools/probe/panel_font_scale.gd` — 25 checks. It asserts the three failures that
      are invisible in source: scaling nothing, RUNNING AWAY on re-apply, and a by-reference loop
      capture pointing all four appliers at the last panel.

- [x] **DONE 2026-09-17 — dungeon grade now follows the LAND, on every path.** The second
      example arrived: owner accepted a Star Hollow quest that routed him into an **E2 (Lv 34-49)
      reachable from country averaging level 14**. Ruling: *"I'm fine with low dungeons (judging by
      the type of monster example being a goblin vs a world eater) being possible in high level
      areas (although they would likely be the appropriate grade, you shouldn't be running into H1
      dungeons in high level areas). The reverse is not okay though, Dungeons should be of
      appropriate level to the neighborhood they are in. Quests should respect this."*

      That separates two things that were tangled: the **TYPE** (goblin vs world eater) stays free,
      the **GRADE** must match the neighbourhood **in both directions**.

      Two paths did not use `_grade_of_land`, which has answered exactly this since 2026-09-11:
      1. `_create_world_dungeon_near` graded by the TYPE's design weight. Its own comment said
         making it consistent was *"the owner's call, not a side effect of a rename."* Called.
      2. **Quest dungeons** graded by `base_tier` + distance-rank with no reference to the land.

      ⛑ **AND MEASURING IT SHOWED BOTH DIRECTIONS WERE BROKEN.** Under the old rule every
      dungeon quest at northwatch graded **1/9 — H9 — in high country**, which is the *"you
      shouldn't be running into H1 dungeons in high level areas"* half nobody had reported yet.

      ⛑ **A RESOLVER, NOT A PARAMETER.** `get_post_anchored_level` is an instance method on
      `world_system`, so `quest_database` cannot compute it. Threading a `land_grade` argument
      would have meant threading it through `get_quest()` as well — five server call sites —
      and `_generate_daily_quest` runs from two places that must stay in exact lockstep (the board
      display and the turn-in reconstruction). The day one forgets, the quest a player turns in is
      not the quest they accepted. `quest_db.land_grade_fn` is a pure function of the post's
      POSITION, so every path gets the same answer with nobody having to remember.
      Probe: a stub resolver drives the advertised grade to 2/3 and 7/8 and every quest follows.

- [ ] ~~**Dungeon level mismatch — BLOCKED, needs a second example.**~~ Owner reported a 1-1 wolf
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

- [x] **Invite window — DONE 2026-09-18, and it was smaller than the line suggested.** Verified
      before building, per the standing rule, and most of it already existed: the server's
      `handle_party_invite` resolves its target **by name** and gates on combat, dungeon, party
      state, a full party, a pending invite and a cooldown - **none of which is a distance**. What
      was missing was any client route except the walk-into-someone bump prompt, so forming a party
      with a player you could see in the online list meant going to find them first.
      Added **Invite to Party** to the player context menu (right-click a name, or the Actions
      button on the player-info popup, which is the controller-reachable door). No client-side
      pre-checks: every refusal is already reported by the server, and a second copy of those
      conditions is the "one value, two places" shape that goes stale.
      ⛑ **Same shape as the Duel-for-Valor gap**, whose comment sits two rows above it in the same
      table: the capability existed server-side and the player could not reach it, so a sweep
      reading *"invites exist"* called it covered. `tools/probe/player_menu_covers_actions.gd` now
      checks that every menu row dispatches AND that both previously-missed verbs are reachable.
- [→] **Watch-a-teammate's-minigame** — **OPTIONAL, moved to the END of the backlog** (owner,
      2026-09-18: *"Minigame watch is an optional, it can go to the end."*). `Watch` in the player
      menu already follows another player's game output; this is only the narrower live-minigame
      case.
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

- [ ] **PATHS NEED A REVAMP — CLASS-SPECIFIC AND LESS CONDITIONAL. Owner direction 2026-09-18:**
      *"Path's need revamped and should be class specific and less conditional."*

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

- [ ] **COMBAT TACTICS / GAMBITS — owner direction 2026-09-18, INTERESTED not committed.**
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
      not.** Owner: *"dungeon reward cards likely need reworked and added to add interesting new
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

- [x] **AN H9 COMPANION BEATS A G1 BY ~3x, AND ASCENDING IS A DOWNGRADE. Owner asked for this  **DONE 2026-09-13.** The GRADE half was already fixed - one tier is worth x1.30 in HP and a G1 now edges an H9 (0.97x), ladder monotonic over all 81 cells. The trap was the LEVEL RESET: ascension and rank fusion both returned a level-1 companion whatever went in (x0.48 at level 20, x0.25 at level 40). Both carry the best input level now; measured x1.03 and rising ceiling. ~~Original:~~
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

- [x] **A WORLD DUNGEON BUILDS ITS WHOLE INTERIOR AND NOBODY EVER LOOKS AT IT.** Found 2026-09-11  **DONE and VERIFIED 2026-09-13** - `tools/probe/lazy_dungeon_interior.gd` PASSES: a dungeon nobody has entered builds no rooms.
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

- [x] **PERSONAL dungeons are never cleaned up on logout or death. **DONE and VERIFIED 2026-09-13** - disconnect starts a 30-min grace, permadeath drops them at once, 24h age cap, swept every 120s from `_check_dungeon_spawns`. Guarded by `tools/probe/personal_dungeon_cleanup.gd`, which checks the reaper is CALLED - three things in this repo have been written and never invoked. ~~Original:~~ Owner 2026-09-11:** *"we need
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

- [x] **A DUNGEON TYPE STOPS OWNING ITS GRADE. Owner direction 2026-09-11, and it is the biggest  **DONE and VERIFIED 2026-09-13** - `tools/probe/dungeon_grade_truth.gd` PASSES; grade lives on the INSTANCE and `force_tier` carries it into the run you enter.
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

- [x] **A DUNGEON CONTAINS EXACTLY ONE SPECIES, and the Atlas advertises otherwise.** Found  **DONE and VERIFIED 2026-09-13** - `tools/probe/dungeon_species_mix.gd` PASSES: a dungeon holds a mix, and its floor eggs follow what actually spawned.
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



- [x] **RANK DOES NOT PAY OFF IN EGGS, which is the reason to climb it. Owner 2026-09-11:**  **DONE 2026-09-13.** Floor eggs follow the dungeon (mean rank 1.51 at rank 1 -> 8.00 at rank 9, rank 9 reachable, rank 1 cannot produce rank 7+), and the FINAL CHEST now rolls gear at the dungeon's own band instead of the looter's level (rank 1 -> lvl 32 gear, rank 9 -> lvl 58, taking the max with the player so nobody who out-levelled it gets less). Guarded by `tools/probe/floor_egg_rank.gd`. **Still open and needing an OWNER DECISION, moved to its own line below.** ~~Original:~~

- [x] **DECIDE: a rank-9 dungeon boss egg is the 2.0x/1.75x tier the tables still label "Fusion-only".** Raising dungeons from 8 ranks to 9 opened that door by accident, and an H9 boss egg now beats anything fusion can make below rank 9. Wants a decision, not a fix: either fusion stops being the only route to the top rank (and is repriced), or dungeon boss eggs cap at rank 8. **Valor now scales with rank too** (2026-09-13) - it was the only completion reward on the chest that did not, while xp and materials both already applied `1.0 + (rank-1)*0.1`. `_open_dungeon_treasure` is confirmed DEAD and is now documented as dead in the code, with the probe asserting the blanking that makes it so - re-enabling treasure tiles will wake the old path and the probe will say so. The CARD REWARD now follows rank too (2026-09-13): a rank-9 run is 1.8x as likely to pay a card as a rank-1, on the same curve, with the 30% ceiling unchanged - 7%->13% at tier 1, 15%->27% at tier 5, capped at tier 7+. Escape scrolls come from the chest consumable roll, which picks up rank through the item level. **Every completion reward now follows the ladder.**  **DECIDED AND BUILT 2026-09-13** - see the decision block above.
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

- [x] **A DUNGEON'S LEVEL AND THE LAND AROUND IT ARE UNRELATED. Owner report 2026-09-11, and it  **DONE and VERIFIED 2026-09-13** - `tools/probe/dungeon_grade_from_land.gd` PASSES: a dungeon's grade is a fact about the land it stands in, and the owner's asked-for exception (a low-type dungeon at a high grade) still works.
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
      sprited once we get all of the overworld spriting in."* **BOTH DONE 2026-09-11.** The
      sprite came with the phase; the hover was built ON the tooltip fixes rather than beside
      them, since it is the same surface, which is why it waited for them. The payload names
      every entrance in view with its NAME, GRADE and the levels inside - with ~3,150 dungeons
      in the world an H4 and an S9 are the same purple marker until you can ask one.

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

- [x] **Zoom the map inside NPC posts** (owner 2026-09-08) — **now part of Phase 2.95 PHASE 2, do  **SUPERSEDED 2026-09-12** - the zoom was REMOVED, measured: a post is 17-20 tiles across in a 23-tile view, so there was nothing spare to crop and the crop was cutting off the doors.
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
- [x] **DUNGEON-THEMED FLOOR EQUIPMENT — DONE 2026-09-17.** Owner 2026-09-08: *"higher chances
      for players to find floor equipment with affixes related to our matching the dungeon type.
      Example Balrog equipment in a Balrog dungeon."* A Balrog's Depths run now drops
      **"Balrog-touched Legendary Ring of the Balrog"**, and every one of the 53 dungeon types has
      a theme.

      **The content already existed — as comments.** 55 of the 120 affix rows named the monster
      they were written for: `{"name": "Balrog-touched", ...},# Balrog`. In a trailing comment, so
      no code could read it. The association was fully authored and completely unusable, and the
      obvious implementation was a second table mapping dungeons to affixes — the same "one value,
      two owners" shape as this week's other bugs, with the copy guaranteed to drift as the pools
      grow. **So the comment became a field.** `"monster": "Balrog"` sits on the row it describes;
      `themed_affix_subset()` reads it; there is no mapping table anywhere. Add an affix and it is
      themed the moment it names a creature.

      **Measured coverage, not hoped-for coverage:** of 53 dungeon types, **43 are themed by their
      boss species alone and 10 more through their floor pool**. The two cosmic dungeons (Chaos
      Sanctum, The Nameless Void) matched nothing, because the endgame cosmic species had never
      been given affixes — six rows closed it to 53/53.

      **Two faults the probe found that the feature would otherwise have shipped with:**
      * **`Draconic` was themed to "Dragon", which is not a monster.** The species is "Ancient
        Dragon", which the matching suffix had said all along. A themed affix naming a creature
        that does not exist is a dead row: never picked, and indistinguishable from one that
        simply never came up.
      * **The first cut wired ONE of five call sites.** `roll_dungeon_chest_equipment` is called
        five times in `server.gd` — the scattered floor roll, the guaranteed floor piece, the
        treasure chest, and the final chest's two rolls — plus a forced fallback that calls the
        generator directly when the 55% gate fails. Only the scatter was themed. A player would
        have seen Balrog gear on the ground and ordinary gear in the chests with no way to
        describe the difference. **Fixed structurally:** `_dungeon_equipment_for(instance_id, ...)`
        is the one door, it **derives** the theme from the instance rather than taking it as a
        parameter, and the probe is a token BAN with an allowlist — a new site that reaches the
        generator directly fails the check. (A probe that *searches for the good call* passes on
        finding one and says nothing about the other four. That is how four survived.)

      **It is a bias, not a bonus, and that was measured too.** 45% per affix slot, so an uncommon
      carries a themed affix ~70% of the time while the other slot stays a free roll — a themed
      item is not a fixed item. Within a stat family a themed affix is worth **1.00x** an average
      one across all 53 types, ranging 0.67x (Rat Warrens) to 1.46x (God Slayer Arena), which is
      the gradient the affix authors built in by matching affix strength to monster strength.
      **No player-power change, so no re-calibration is owed.**

      ⛑ **And the first version of that power measurement was unsound** — it summed raw affix
      values across different stats, where one hp affix (40 + 6/level) outweighs every attack
      affix in the pool (7 + 1.2/level). A Balrog dungeon has no hp-themed affix, so biasing
      toward its own creatures moved the roll off hp and the sum fell 11%. That is a change of
      stat MIX, which is the intended effect, read as a loss of power. Fixed by comparing
      **within** a stat family, which is one unit and can be compared.

      Probe: `tools/probe/themed_floor_equipment.gd` — five sections, and all four of its
      fault-detecting checks were proven to fire by re-injecting the faults (bias chance to 0, one
      call site back to the raw generator).

- [x] **Dungeon Atlas** as hub + quest board. — **DONE 2026-09-17.** It is a TAB of the quest
      panel now, not a screen of its own: one shell, two doors, and the difference carried by the
      verb each row offers (Dungeons rows Locate, Quest rows Accept / Turn In / Abandon). A quest
      PINS its dungeon at the top, naming what is wanted, the progress, and the post to hand it
      in at — because that tab deliberately cannot accept anything. Rumours display and name
      where they were heard. Every row judges the place against your level in the same words the
      dungeon entrance screen uses. The text Atlas and the orphaned text dungeon LIST both
      retired, and no button points at either. Probe: `tools/probe/atlas_pins_and_rumours.gd`.
- [x] **Dungeon-centred questing** to replace the disliked overworld quests: clear / rescue /
      boss-hunt / gather. — **ALREADY BUILT (P2, 2026-08-26). Ticked 2026-09-16 after an audit,
      not after work.**

      The owner asked to start the arc *"and we should ensure some of it hasn't been done
      already"*. This is the shipped-but-unticked case that warning exists for.

      Verified by following the call path rather than by reading the item:
      `get_available_quests_for_player` - the ONLY quest source the board uses - returns just
      `generate_dynamic_quests`, whose pool is the `DYNAMIC_QUEST_TYPES` constant:
      `[DUNGEON_CLEAR, RESCUE, BOSS_HUNT, GATHER]`. Exactly the four this item names.

      The overworld types are **not** in that pool. `KILL_ANY`, `KILL_TYPE`, `KILL_LEVEL` and
      `HOTZONE_KILL` survive only in `_generate_quest_for_tier*`, which the dispatcher reaches
      solely for quest ids containing `_dynamic_` - commented in the source as *"legacy dynamic
      quest IDs"*. Live quests use `_daily_` ids and never touch it.

      **What was nearly built on top of a finished feature:** a plan to "replace the overworld
      quests" would have found them already replaced, and the obvious next move - editing the
      type pool - would have edited a constant that is already correct.
- [x] **Presentation pass — mostly SHIPPED, one piece left.** The map, minimap and in-dungeon  **DONE 2026-09-13** - `docs/img/dungeon.jpg` is live on the features page under the Dungeons section. The capture scene now walks an 18-step route instead of 3, because the short one left two-thirds of the frame black: fine for checking a sprite, useless as a picture of the game.
      GUI all landed across v0.9.760-767. What remains is narrow: **real in-game dungeon
      screenshots for the website**, which now show something worth showing.

## Phase 6 — realm meta and sinks

- [ ] **Real sinks for excess eggs and companions**: shops, breeders, trainers, fusers, companion
      tasks. Much is already scaffolded (fusion, breeder NPCs, egg market, kennel).
- [ ] **Living world / rework the posts.** Designed 2026-09-04 as **step 4 of the companion
      spine**, and the detail is in `docs/archive/BACKLOG_journal_to_2026-09-07.md` (item 16) —
      not undesigned, just archived. Scope: companions living around the posts, **NPCs, wandering
      travellers and recruitable party members**, and threats woven into the posts rather than
      sitting beside them. It follows the companion drops and the egg/companion sinks because it
      is what those populate. **Overlaps the player-phantom prefab tiers** (a bought post's quest
      boards and workstations are the player-owned half of the same idea) — design the two
      together or the post will have two unrelated populations.
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
- [ ] **CRAFTING REASSESSMENT — scoped by the owner 2026-09-17, and it is most of the system.**
      Asked how much of crafting was in scope, the owner answered *"Most of it"*: *"Players gather
      a bunch of materials and don't really have useful things to do with them. It is all too
      difficult to understand for them currently. Ideally they should have clear options that
      obviously benefit them to do. Currently it's a pain to craft and you're often making things
      with no real value or use just to try and level up your crafting skill. I'd say all of the
      craftable items and options need to be reassessed and we need a clear path that speaks to
      the identity of each type of crafter. We want interesting options that are beneficial for
      players rather than grindy crap that no one wants."*

      Four faults named, and they are separate problems:
      1. **Materials have no destination.** Gathering produces a pile the player cannot spend on
         anything they want. (Pairs with the egg/companion sinks — same disease, different
         resource.)
      2. **It is not understandable.** The recipe surface does not tell a player what to make or
         why. This is a UI/legibility job as much as a content one and belongs with the UI audit.
      3. **The output is worthless.** Players craft to raise the skill, not to get the item — the
         tell that recipe outputs are not sized against what drops.
      4. **No crafter identity.** Each crafting job needs a **clear path** that says what that
         kind of crafter is FOR, so choosing one is a choice.

      **Not to be confused with item 18 in the archive, "Craft review"** — that is auditing the
      *game* against industry standards, a completely different task that happens to share a word.

      **Do first, before any recipe is touched:** enumerate what crafting can currently produce by
      **executing the tables** (`shared/crafting_database.gd`) rather than reading them, and price
      each output against what a dungeon of the same level DROPS. Fault 3 is a claim about
      relative value and cannot be judged without both numbers. Same rule as the equipment
      reference: walk the acquisition paths, do not enumerate the pools.
- [ ] **SANCTUARY UPGRADES ARE PRICED OUT OF REACH, AND THE LADDER IS DULL. Owner direction
      2026-09-18:** *"Sanctuary upgrades via baddie points need revamped. Don't like the current
      sanctuary balance (starting egg slots, companion kennel spots, kennel spots, etc.) most of
      the choices take too many baddie points, players are playing lots of characters and still
      not having enough for upgrades. We need more interesting upgrades possibly branching ones
      even."*

      Three asks: **the prices are too high**, **the named slot upgrades are the wrong shape**, and
      **the ladder needs more interesting — possibly branching — choices.**

      **⛑ MEASURED ON THE LIVE SERVER 2026-09-18, AND IT IS WORSE THAN THE COMPLAINT.** My first
      pass at this estimated ~500-600 BP per death from the formula and a level-22 character. That
      was wrong, and wrong in the direction that matters - **the level-22 character was my test
      character, not a player.** The owner: *"I don't know if your estimation of how many valor
      players are usually getting is correct."* It was not. Read off `leaderboard.json` (81 real
      deaths) and `houses.json` (13 accounts):

      **Where players actually die.** Median death is **level 3**, mean 5.8, median XP at death
      **355**. Restricted to the last 7 / 14 / 30 / 60 days the median is 4 / 3 / 3 / 3 - so this is
      not an artefact of old characters from a different balance era, which was the owner's
      specific worry. Of 60 deaths in the last 60 days, **46 are at level 5 or below**; two are
      above level 21.

      At a median death that is `355/100` = **3 BP from the XP term**, plus 0 from kills (median 9,
      and it pays per 10), plus quests and gems, and **no level milestone at all** - the first is
      at L10, which 80% of deaths never reach.

      **What accounts have actually earned, ever:**

      | | BP earned (lifetime) | unspent | upgrade levels owned |
      |---|---|---|---|
      | best account | 7,022 | 1,672 | **4** |
      | 2nd | 4,307 | 7 | 3 |
      | 3rd | 1,878 | 878 | 2 |
      | median of 13 accounts | **0** | 0 | 0 |

      Seven of thirteen accounts have earned **zero**. The most invested account in the game has
      died 45 times (~156 BP per death, lifted by two rare high-level characters) and owns
      **gathering_bonus 1, resource_regen 1, storage_slots 2**. Its 1,672 unspent is not enough for
      one `companion_slots` level.

      **⛑ AND THE DECISIVE NUMBER: NINETEEN OF THE ~25 UPGRADES HAVE NEVER BEEN BOUGHT ONCE, BY
      ANYONE.** Across every account in the game, six upgrade types have ever been purchased, nine
      levels in total. Every upgrade the owner named by hand - `companion_slots`,
      `kennel_capacity`, `egg_slots` past level 1 - is in the never-bought set, along with
      `house_size`, `post_slots`, `xp_bonus`, `hp_bonus`, `flee_chance` and all six stat bonuses.
      That is not an expensive ladder, it is an **unreachable** one: most of the content has never
      been seen by a player.

      (13 accounts is a small sample and the game is young - but the finding is not a rate, it is
      that a majority of the content has zero purchases, and that does not need a large n.)

      **☑ STEP 1 (the measurement) IS DONE — it is the block above.** What it changes about the
      job: this is not a price cut. A ladder where 19 of 25 tracks have never been touched is not
      mispriced at the margin, it is out of reach entirely, and shaving costs by 30% would move
      nothing. The two things to settle are **what a death should be worth** (the curve pays almost
      nothing below L10, which is where essentially every death happens) and **what the first rung
      of each track costs**, since no track is ever entered.

      **On branching:** the current ladder is 20+ independent linear tracks, which is why it is
      dull — nothing is ever given up. Branching means a choice that EXCLUDES something, and that
      only reads as interesting if the alternatives are legible at the point of choosing. Design
      the exclusions before the content, and see the Paths item above: it is the same failure mode
      (a wide menu of small always-good increments is not a decision).

      **⛑ SEQUENCING — this comes BEFORE the Sanctuary redesign below, deliberately.** That item
      asks where the Sanctuary physically LIVES; this one asks what it is worth visiting for, it is
      the live complaint, and it is independently shippable. But if both are done in one arc, do
      the economy first: repricing a ladder and then discovering the redesign replaces half of it
      is the wasteful order. **Baddie points are NOT valor**, so this does not wait on the
      realm-wide valor economy pass — the two currencies can be settled independently.

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
- [ ] **PLAYER PHANTOMS — the outward loop.** The whole design already existed and this list had
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
- [ ] **Minigame variety.** Item 17 in `docs/archive/BACKLOG_journal_to_2026-09-07.md`, and it
      is concrete: **port the Chain / Mystery / Trap mechanics from combat loot to gathering and
      crafting** (the combat slice shipped as v0.9.644-645), plus **trap chests, a Mimic chest
      variant, and the 2 remaining dungeon-exclusive consumables**. It is the same list as the
      Prize Shuffle line above from a different angle — fold them when either is started.
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
