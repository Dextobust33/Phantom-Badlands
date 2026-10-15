# Master Backlog - CLOSED items moved out 2026-10-15

Everything below was a ticked ([x]) or withdrawn ([✗]) top-level item of `docs/BACKLOG.md`,
moved here verbatim and in original order by `tools/backlog_prune.py`. Search this file before
re-opening anything: several entries record why an approach was REJECTED.

---

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

- [x] **✅ PARTY PLAY FOLLOWS THE DRAGON QUEST IX MODEL — COMPLETE 2026-09-19 (v0.9.833).**
      Owner direction 2026-09-18, finished on the owner's ask to close the arc.

      **What shipped, in two sittings:**
      * **Independent movement.** All four follower locks gone (movement, hunting, resting,
        gathering) and BOTH snakes deleted - overworld and dungeon. Each teleported followers onto
        the person-ahead's tile every step, which makes independent movement meaningless.
      * **The proximity pull.** ANY member's encounter starts the party fight, bounded by
        `PARTY_PULL_RADIUS` (8, Chebyshev, against a 23-tile view). Out-of-range members are named
        rather than silently dropped. Applies underground too.
      * **The map indicator.** `in_combat` now rides the overworld player payload (the DUNGEON
        payload always had it), a fighting party member is tinted on the map, and the hover says
        *"fighting — walk into them to join"*. Party members only: a stranger's fight is not one
        you can join, so marking it would point at a door that is not there.
      * **Run-in join.** Walking into a fighting teammate joins their fight.

      ⚡ **THE RACE RESOLVED ITSELF** - no tie-breaker was built. The server handles triggers one
      at a time, so the first claims the party's combat and sets `in_combat` on everyone it pulls,
      and the second is turned away by a check that already existed.

      ⚡ **THE MONSTER'S HP IS NOT RE-SCALED ON JOIN**, and that is the trap this item named.
      `start_party_combat_simul` multiplies max HP by party size at the start, so the naive
      "one more member, one more multiple" would make a rescuer arrive and HEAL the thing they
      came to help kill - the fight getting longer the more help turns up. A joiner adds damage to
      the bar where the fight left it.

      ⛑ **A JOINER ARRIVES BETWEEN ROUNDS.** `_party_all_submitted` gates the round on the member
      list as it stands, so they are marked as having already acted for the round in progress and
      act from the next - which is also the honest reading of having just run in. They are dealt
      their own deck and opening hand, or they would be in the fight and unable to act in it.

      **Verified-before-built, and most of it already existed:** dungeon party ENTRY places a whole
      party into one instance, `_try_start_dungeon_coop` already ran shared combat underground, and
      the dungeon payload already drew other party members (added when the owner reported *"map
      shows one player sprite and its companion, no party members"*). The new work was the ENTRY
      into combat, not the fight.

      Probe: `the_party_fights_together.gd`, covering all four pieces, proven to fire on the HP
      re-scale and the between-rounds rule.

      **Not built, and deliberately:** the **Muster Sigil** (join from anywhere) was parked against
      this arc. With the run-in join working, decide whether it is still wanted before building it.

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

- [✗] **ACTION POSES — REMOVED FROM THE BACKLOG 2026-09-18, owner's call.** *"Action poses should
      be removed then if you can't fill in the other 40 from the templates like we discussed."*
      **Could not be, and it was measured rather than assumed:** `$tf_template.png` carries **walk
      cycles only** - 12 frames, four directions, three steps - so there is no template action pose
      to copy FROM. The sword-raises and casts in `expansion/animation1.png` were drawn per
      character on top of the shared skeleton. Two characters agree on 89% of their silhouette, but
      the 11% that differs is exactly the part that MOVES: hair, cape, sleeve, weapon. When the arm
      goes up the sleeve goes with it, and that sleeve belongs to the target character - so a
      transfer means segmenting clothing from body per sprite and redrawing it.
      Kept as a record of the measurement so the question is not re-asked. Coverage as it stands:
      `chara1-5` (40) have laugh / nod / pose / shake / surprise; `military1-3` (24) have pose only;
      `npc1-2` (16) have walk frames only. If there is ever appetite it is authored ART.

1. - [x] **DONE 2026-10-13 [21] "31 parse errors in Godot".** Cause: the archived legacy simulator
      (`tools/combat_simulator/archive/`) preloaded siblings from the pre-archive path, and the
      editor reopens `quick_simulation.gd` from its saved open-tabs list. Preloads repointed into
      `archive/`; a full `--headless --editor --quit` load now prints zero errors (was 5 lines,
      expanding to ~31 in the editor).

2. - [x] **DONE 2026-10-13 — MAP DRAWS OVER A PANEL THE PLAYER IS READING** [2 Rework, 3 Inspect
      gear, 8 Salvage, 11 Home Stone companion page, 23 Settings, 46 Titan wish result]. Every
      one photographed BEFORE and AFTER with the harness (`shots.py invpath | pagepath | wishpath`),
      which drives the real click path and prints canvas-ownership state beside each capture.
      The suspected cause (server refresh wiping `game_output`) was WRONG; there were two causes:
      (a) `update_map`'s ~0.4s idle-bob redraw protected only WIDE pages, and Rework/Salvage/
      Sort/Inspect/Settings/Home Stone pages are short or flag-driven, so the map was painted
      over them within a tick; (b) every `location` message closed a wide page ("walking away"),
      and the server sends one when ANY nearby player steps - the owner's Settings guess was
      right. Fix: one predicate `_canvas_held_by_page()` = wide page OR `_menu_mode_holds_canvas()`
      (inventory/settings/home_stone modes), read by `update_map`, `_ow_heal_canvas` and
      `_ow_text_in_column`; the location handler no longer closes a page a mode holds.
      (c) [46] the wish result was printed while the combat scene still owned the canvas, so it
      landed behind the scene and the map repainted over it; it now rides the victory card (with
      level-up) like a normal kill. Probe `a_menu_page_owns_the_canvas.gd`: fault-injected on
      each guard (update_map, location handler, modes list, wish card) and fails every time;
      the three existing canvas probes still pass.
      **Honest gaps:** [3] a SHORT gear page now holds (photographed) but I did not take a
      pre-fix baseline for a short gear page, so that one is "consistent with the cause", not
      separately reproduced. Other `*_mode` screens (market/crafting use real panels; wish
      PROMPT, monster-select, target-farm, title menu) were not photographed - add a flag to
      `_menu_mode_holds_canvas()` if any is reported.

3. - [x] **DONE IN CODE 2026-10-13 (server fix — NOT YET DEPLOYED, see below) — [5] Wyvern threat
      quest: never shown inside, "already in a dungeon", relog lands at the Crossroads.**
      Cause, reproduced with the real entry path (`tools/probe/threat_quest_entry_has_an_interior.gd`)
      and matched to the live log (Sep 21 16:03: *"Bound threat-relief quest ...@wyvern_roost to
      WORLD dungeon world_dungeon_3563"* -> *"Player Dexto entered dungeon Wyvern's Roost
      (instance world_dungeon_3563)"* -> relog *"Dungeon world_dungeon_3563 expired ... returning
      to overworld"*): a THREAT-RELIEF quest binds to the WORLD dungeon itself, and world dungeons
      build their interior LAZILY (`_ensure_dungeon_interior`, 2026-09-11, justified by "entering
      creates a personal instance, nothing reads the world one's floors"). `handle_dungeon_enter`
      never asked for it, so it read floors that did not exist. A debug build stops at the missing
      key; the RELEASE server carries on with null, flags the character inside, and
      `_send_dungeon_state` silently `return`ed (no floors) - so the client was told nothing, every
      retry answered "already in a dungeon", and the next login saw no interior and ejected you.
      It is NOT specific to Wyvern or to APEX grade: any threat-relief quest does this (the log
      shows the same binding for Ogre Bog and Orc Stronghold). Two theories were disproved first by
      measurement: instance GENERATION at every grade (3/6/9) and the `dungeon_state` payload both
      build cleanly, and a plain Wyvern entry in a real client works.
      Fix, both layers: (1) `handle_dungeon_enter` builds the interior before anyone is put in
      it, and refuses with a message if it cannot; (2) `_send_dungeon_state` no longer returns
      silently - a character flagged inside a place with no interior is returned to the overworld
      and told, so the stranded state cannot persist whatever the next cause is. Both guards are
      fault-injected (removing either fails the probe). The `[LAZY-DUNGEON]` log line now names the
      two legitimate callers instead of calling every one a bug.
      **⚑ NEEDS A SERVER DEPLOY to reach players** (client unchanged by this fix). Anyone currently
      stranded is freed by the deploy: their next dungeon action/login now ejects them cleanly.
      **Also found, not fixed (pre-existing, fails identically on committed code):**
      `tools/probe/dungeon_instance_match.gd` — "1 definition + 3 call sites ... got 5" is a stale
      call-site count; re-read what the 5 are before bumping the number. Related to item 36 (the
      log shows a quest released a shared world dungeon "not erased - it is shared", which is
      correct; the abandoned-PERSONAL-dungeon cleanup is the part still to verify).

4. - [x] **DUNGEONS - ALL SIX SUB-ITEMS ADDRESSED 2026-10-13 (see each; [10] and [37+42] have OWNER DECISIONS left)** [1 Rescue-the-Scholar NPC not spawned / glyph text should be sprite, likely all
      NPC quests; 10 random dungeons not on map; 36 abandoned-quest dungeon cleanup; 37 + 42 floor
      loot level/valor not matching dungeon (L56 loot vs L83 monsters, E8 low valor); 35 do
      dungeons ever give a card]. **Sub-status (update as each lands):**
      - [x] **[1] DONE IN CODE 2026-10-13 (server + client; needs server deploy + client release).**
        Measured, not guessed: `tools/probe/rescue_npc_is_reachable.gd` builds 54 real rescue
        instances. TWO defects, the second hidden behind the first. (a) `_find_npc_spawn_position`
        called `room.get("x")` on `Rect2i` rooms; a release server yields null instead of aborting,
        no room qualified, and EVERY rescue NPC was placed at the default (1,1) - a map corner.
        (b) Fixing (a) showed all 54 NPCs standing on the EXIT tile (the farthest room's centre is
        where the stairs are); `handle_dungeon_move` handles EXIT before the NPC check, so stepping
        there just descended - the NPC could never be rescued, and its sprite hid the stairs.
        Placement now picks plain floor nearest the room centre, avoiding stairs/specials/monsters/
        loot. **"Glyph" -> sprites:** NPCs draw from the player sprite pool, one fixed figure per
        kind (scholar 2_7, healer 4_6, merchant 2_5, blacksmith 5_3, breeder 4_3), photographed
        with `shots.py rescuenpcs`; the quest text and the redirect message no longer say "R glyph".
        **It was the same for ALL the NPC rescue quests** (merchant/healer/blacksmith/scholar/
        breeder share this one spawner), as the owner suspected. (The cyan R was also drawing as a
        PURPLE letter - the nearest baked glyph colour - moot now.)
      - [x] **[10] DONE 2026-10-13, shipping in v0.9.834 - random dungeons not on the map. OWNER
        DECIDED: weight spawns toward players.** Implemented (below) as `PLAYER_SPAWN_SHARE = 0.4`
        of world-dungeon rolls placed 20-140 tiles from a random ONLINE overworld player (uniform
        otherwise and whenever nobody is online; players underground are skipped - their
        coordinates are dungeon coordinates). Checked for the "future issues" the owner asked about:
        dungeons live <=24h so nothing clusters permanently; `MAX_DUNGEONS_NEAR_POST` and the threat
        gates still apply to every candidate so a post cannot be buried; the GRADE is still read off
        the land (an easy dungeon cannot appear in hard country). **Known consequence, accepted:**
        the world's grade MIX now follows where players stand rather than staying fixed - which is
        the point, but it means dungeon-grade statistics from live data after this date are not
        comparable with before. Probe: `world_dungeon_roll_is_uniform.gd` (40.0% near players,
        none closer than 20 tiles, underground ignored). The two knobs are the constants beside
        `_roll_location_near_a_player`. **History of the item:**
        The renderer is fine (the capture harness shows entrances; `get_visible_dungeons` sends
        everything inside the minimap's reach). It is SCARCITY, in two parts. (a) **A real defect,
        fixed:** `_roll_location_in_world` sampled a disc of radius 2828 and CLAMPED it into the
        +/-2000 square, so **36.2% of every world dungeon was dragged onto the world's edge** and the
        centre got 0.65x a uniform spread (the caller's "reject out of bounds" check could never fire).
        Now sampled in the square: 0.1% on the edge, centre 1.02x uniform
        (`tools/probe/world_dungeon_roll_is_uniform.gd`). Live dungeons live <=24h, so the world
        re-mixes itself within a day of the deploy. (b) **The design density, NOT changed:**
        `MIN_WORLD_DUNGEONS = 3000` over a 16M-tile world is one per ~5,300 tiles - about 10% of
        squares have one inside the main map's 23x23 view and ~70% inside the minimap's reach - and
        low-grade dungeons can only exist near posts (capped at `MAX_DUNGEONS_NEAR_POST = 6` within
        40 tiles). Those figures are ARITHMETIC FROM THE CONSTANTS, not measured in a live world.
        **OWNER DECISION:** raise the count, or weight spawns toward where players are (the low-level
        country around posts), or add a "dungeon sense" (Atlas/compass already exist). Overlaps the
        Dungeon Atlas work and sheet item 11(a) (what boards offer).
      - [x] **[36] DONE IN CODE 2026-10-13 (server; needs deploy).** Answer to the owner's question:
        yes, abandoned/completed quest dungeons ARE erased (`_cleanup_player_dungeon` on abandon and
        completion; a sweeper reaps personal dungeons 30 min after the owner goes offline or at 24 h;
        a SHARED world dungeon bound by a threat quest is deliberately released, not erased). **The
        gap was occupants:** `_erase_dungeon_instance` never asked who was inside, so abandoning a
        quest from within its dungeon stranded the character flagged inside nothing (same stranded
        state as [5]). Now the one erase function ejects anyone inside, with a message - which
        covers abandon, completion and the sweeper at once
        (`tools/probe/erasing_a_dungeon_never_strands_its_occupants.gd`, failed 3 checks before).
        **Not verified:** whether `player_dungeon_instances` can hold entries for a quest the log
        no longer has (e.g. a daily that rolled over) - the 24 h sweeper bounds the cost either way.
      - [x] **[37 + 42] DONE 2026-10-13, shipping in v0.9.834. OWNER DECIDED: floor coins go up
        now.** Coins now pay `0.5-1.5 x the floor's level` per pickup (never below the old
        `2-6 x tier`): measured on 24 real deep dungeons the average coin went from ~16-22 to
        ~42-61, about 1.0x the monster level on that floor; anchored to the quest model's own slope
        (3.5 valor per level per task) so a run's ~4 coin pickups land near one quest task. Still
        interim - the realm-wide valor economy pass owns the real magnitudes. The rest of this entry
        is the original analysis; ITS "NOT touched" valor note is superseded by this paragraph.
        **(original) LEVEL DONE IN CODE; VALOR MAGNITUDE was deliberately not touched:** The owner's numbers fall out of the code exactly: floor loot was
        rolled at the dungeon's flat base level, monsters at `base x (1 + floor x 0.07)` - and
        56 x (1 + 7 x 0.07) = 83. Measured on 24 real deep instances
        (`tools/probe/floor_loot_matches_the_floor.gd`): equipment a flat **L43 on every floor while
        monsters climbed L42 -> L59 (floor 7 = 73%)**; now **102-104% on every floor**. Fixed for the
        scattered loot AND the guaranteed gear piece via one helper `_dungeon_floor_mult`, reading
        the same `FLOOR_DIFFICULTY_PER_FLOOR` the monsters use. Coins now scale by the same ramp
        (~16 -> ~22 over seven floors). **NOT changed: the base coin amount (`2-6 x tier` per pickup,
        8-24 at an E-grade dungeon).** That is what makes "very low valor on an E8" - and valor
        magnitudes are explicitly the realm-wide VALOR ECONOMY pass's call (the quest anchor is
        marked PROVISIONAL in `quest_database.gd`, and the owner said valor costs "likely need
        rebalanced across the realm"). For scale: a completion chest pays ~`(3-5) x tier x 5` =
        60-100 at tier 4, a quest task ~`3 + 3.5 x level`. **OWNER DECISION** if floor coins should
        be raised before that pass. Chests were already `max(player level, band)`, so unchanged.
      - [x] **[35] ANSWERED 2026-10-13, plus one line of logging (server; needs deploy).** Yes - but
        ONLY on completion (killing the final boss), never from floor loot or chests: each completed
        dungeon rolls `min(30%, (5% + 2% x tier) x (1 + 0.1 x (rank-1)))`, i.e. ~7% at tier 1, ~13% at
        tier 4, 30% ceiling. It grants the dungeon's own themed exclusive card, falling back to a copy
        of an ability you use if you already own 3. The completion screen states the odds
        (`dungeon_card_odds_spoken`). **The honest gap:** the live log had no record of any roll, so
        "do they ever drop" could not be answered from data. Added a `[DUNGEON-CARD]` log line per
        completion (chance and outcome); read the live rate with
        `journalctl -u phantom-badlands | grep DUNGEON-CARD` after the next deploy. If the owner
        feels that is too stingy for a run that takes this long, the knob is that one formula - but
        it belongs to the CARD CHASE design (memory `project_card_instances_chase_loop`), not a
        one-off tweak.

6. - [x] **ALL SEVEN DONE 2026-10-14 - COMBAT MECHANICS TO VERIFY** [4 Swift Hobgoblin landed 6 hits; 9 Distract debuff not
      shown/applied; 28 "less often / once per fight" upgrades functioning?; 40 audit artifact +
      special-effect gear vs their text; 14 runes can't be applied; 34 Tome of Gambit card not in
      deck; 51 same companion registrable in several slots]. (**34 DONE 2026-10-14, server:** the tome pool spans all three paths but the deck deals only the class's own cards, so a Fighter reading a Gambit tome lost it for an inert card; `_use_ability_tome` now refuses a foreign card BEFORE spending the tome - probe `tome_card_reaches_deck`. ALSO DONE (owner chose 'mostly finder's path'): fresh tomes are marked `tome_unaimed` and `Character.add_item` re-aims 80% at a card the finder can play (measured 86-87% usable); market/trade tomes are never re-aimed. **50 DONE (4 slices, owner decisions 2026-10-14) - GOLD IS BACK, per character.** It lives in `gold_purse`, NOT the retired `gold` field (a login migration converts that to Valor and would eat the purse). All numbers are in ONE table, `shared/gold_economy.gd`, and ALL ARE FIRST GUESSES - nothing was measured. (1) kills pay level-scaled gold, solo AND party (boss x4, +50% per empowered mod); gems sell at 1,000 each from the merchant's 'Sell Gems' button; HUD shows Gold beside Valor. (2) salvage (9 paths), quest turn-ins, dungeon clears (graded by the INSTANCE tier) and floor gold piles (8% of floor rolls, taken out of the valor share) all pay - salvage is level x rarity, NOT item value (an L50 epic lists at 26,000; I first paid half of that and caught it before shipping). 'Selling' gear is the Open Market, which stays Valor. (3) a corpse keeps a random 10-50% of the purse - the rule gems already used, now one function. (4) THE SINK: Blacksmith > Temper, up to 5 tiers per worn item for gold (500 / 900 / 1,620 / 2,916 / 5,249 at L50), +damage on a weapon, +HP on everything else, capped, lives ON the item. Probes `gold_purse_core`, `gold_income_sources`, `gold_survives_death_in_part`, `gold_buys_capped_gear_tiers`. **OPEN FROM IT:** (a) BALANCE BATCH - temper gains are player power (L50 weapon +6 damage/tier, armour +45 HP/tier) and every price/payout is untuned: run `-- preflight` then the chain once, then compare gold income per hour against the 5-tier cost; (b) DONE 2026-10-14 (owner: yes): the ENCHANTER's gold sink is REWORK - priced in gold instead of Valor (`GoldEconomy.rework_gold`, 4 x level x (1 + 0.6 x reworks done): 200 -> 560 at L50), a committed Enchanter still pays no gold but always pays materials - probe `rework_costs_gold_and_keeps_temper`; (c) Valor prices were left untouched (owner chose 'Valor = market/services, gold = gear power'); (d) DONE 2026-10-14 (owner: yes): a tempered stat now SURVIVES Rework - the bought amount is recorded per stat in `item.temper_gain`, Rework rerolls only the natural part (reported old value is the natural one), a tempered-only stat is not reworkable, and a reroll can never merge onto it; (e) FIXED on the way: Disenchant (`_craft_disenchant`) crashed on EVERY use - it iterated get_salvage_value()'s {materials: {...}} as a flat dict (Nonexistent float constructor - silent on a release server) - probe `disenchant_recovers_materials` (fails on the old code); (f) no help-page / changelog text yet for gold, auto-spend or the salvage toggle - add at the next release. **GROUP 10 (owner decisions 2026-10-14): 7 DONE** - single-item salvage prompt is a Settings > Game toggle ([0] / 'Salvage Ask' button), default ON, bulk salvages always ask; auto-salvage (pickup AND make-room) never eats an item that would beat or fill a worn slot (`Character.is_probable_upgrade`: empty slot, or strictly better rarity at >= level) - probe `salvage_asks_and_spares_upgrades`. The 'market-listing popups' half of 7 was NOT found/changed - ask what it meant. **29 DONE** - each level's stat point is auto-spent on the class preset (`Character.preset_stat_for_class`, the SAME rule the simulator's reference player uses; the sim now calls it), opt-out button in the Stats panel, points already banked are never touched, saves from before load as ON - probe `stat_points_auto_spend`. BALANCE BATCH note: players who forgot to spend now have the stats the reference player already assumed. **30 DONE** - auto-skip pace now scales with the pick count (`client/autoskip_pace.gd`, one rule): a whole run takes ~3s however many reveals (floor 0.05s, base gap for short hauls) for BOTH the combat loot panel and the gather/craft scratch-offs; the owner offered 'fewer reveals OR faster auto-skip' - the REVEAL COUNT (budget x5) was left alone because cutting it is an economy change. Probe `autoskip_pace_scales_with_reveals`. **40 DONE 2026-10-14 (uniques + sets; see the gap below), server:** all 27 unique/set effect keys have a consumer through the funnel, and the consumers I read match their text (death save, kill cleanse, Time Anchor, flee, valor, XP, loot reveal, double cast). The real mismatch, found by an A/B at +100 with the same weapon in both arms: `attack_damage_pct` ('+X% attack damage', Bloodletter's Hook, plus Path's Sharpened Edge) multiplied basic attacks x1.98 and CARDS x1.01 - nearly dead in a deck game - while `spell_damage_pct` ('+X% spell damage', Cinderheart Staff) multiplied EVERY class's cards x2.0. Inverted. A card now has a school: a mage's cards take spell power, every other class's take attack power. Probe `unique_damage_keys_follow_their_text` (fails on the old code). **BALANCE BATCH:** a player-side change - non-mage Path nodes with attack_damage_pct now actually reach their cards. **NOT AUDITED:** non-unique artifact-rarity gear and proc runes (lifesteal/shocking/...) vs their text; the bleed/burn/crit-bleed and clutch-time-stop effects were read, not A/B'd. **14 DONE 2026-10-14, client:** runes could not be applied from the inventory PANEL - its Use sent a bare `inventory_use` and the choose-a-slot flow lived only in the old text inventory, where the slot choice was number-keys behind a DISABLED '1-9 Select' label. Panel Use now enters the flow, the slots are real buttons (keys 1-5 still work; both land in `_apply_rune_to_slot_choice`), and the result is held for reading. Probes `a_rune_can_be_applied_from_the_panel` (fails on the old client) + `rune_applies_on_the_server`. State is verified headless; the PIXELS are not - wants one look in the live client. **28 DONE 2026-10-14, server:** the two upgrades behind 'less often / once per fight'. HEAVY DRAW (+25% damage, 'slower to come back around') had NO drawback at all - the damage code said 'handled by the deck' and the deck did nothing, so it was a free +25%. A Heavy Draw card now goes to the BOTTOM of the reshuffled deck (stateless, nothing to lose across saves/party views). SACRIFICIAL ('spent for the rest of the fight') kept returning as a dead draw that whiffed and wasted the turn; a spent card now stays out at the next reshuffle (solo; a party view carries no fight flags, so there it still whiffs). Probe `heavy_draw_and_sacrificial_cost_something` (fails on the old code). **BALANCE BATCH:** this makes two upgrades WEAKER, so it is a player-side change - include it in the next chain run, do not run it per item. **9 DONE 2026-10-14:** Distract IS applied (monster damaged the caster in 40% of actions after it vs 62% after a plain attack) but was never SHOWN - the monster's turn resolves inside the cast and erases it, so the chip was visible in 0 of 400 casts. The monster's turn now says 'Distracted - the X's aim is off (-N% accuracy)' where it bites - probe `distract_says_when_it_bites`. **4 DONE 2026-10-14, client:** NOT a combat bug - a Swift monster lands 2-3 hits per turn (measured over 1,500+ real actions, max 3). The round-summary line counted MESSAGES as hits, so 'attacks multiple times!' / 'strikes with unexpected ferocity!' / misses all inflated it to 6-7. A hit is now a line carrying a measured dmg/taken number - probe `summary_counts_hits_not_lines` (fails on the old code). A multi-hit monster turn now reads 'attack' with the real count in the hover prose. **51 DONE 2026-10-14, server:** owner screenshots showed one Lime Hydra in two slots (Lv17 checked out, Lv53 available). ROUTE, reproduced on the old code: the Stable deposit asked 'registered?' only of the ACTIVE companion, so a registered companion in the collection was copied to the kennel with its slot flag stripped and kennel->Register made a second row. Deposit now asks `_is_registered_companion` of THIS companion and returns it to its slot; `register_companion_to_house` also refuses a duplicate id and the kennel Register puts the companion back instead of losing it - probe `deposit_never_copies_a_registered_companion` (fails on the old code) + `one_companion_one_slot`. Existing duplicate rows in live Sanctuaries are not cleaned up by this.)

10. - [x] **DESIGN ASKS — DECIDED AND BUILT 2026-10-14 (7, 29, 30, 50; see the GROUP 10 note in the handoff block)** [7 salvage confirm toggle + auto-salvage
      vs equipped gear + market-listing popups; 29 stat-point auto-apply; 30 minigame too long late;
      50 bring gold back, 1 gem = 1k gold, blacksmith/enchanter sinks into HP/damage].

13. - [x] **DONE 2026-10-13 (tooling; shipping with v0.9.834) — THE SILENT-SCRIPT-ERROR CLASS.**
      Three live bugs in one day (threat-quest entry, rescue NPC placement, a player stranded in an
      erased dungeon) had one cause the owner asked me to retire: **the exported server is built
      without GDScript's debug checks, so a script error does not stop anything and prints
      nothing** - `Invalid access to property or key` just yields null and the code carries on into
      a corrupt state. The live journal held no trace of any of them. Only a DEBUG run prints the
      error, and nothing read it: probes could print `SCRIPT ERROR` and still say PASS with exit 0,
      and `tools/test_setup/shots.py` sent the SERVER's output to DEVNULL. Fixed at both layers:
      (1) **`tools/probe_run.py`** judges a probe on four things - exit status/timeout, its own PASS
      verdict, NO `SCRIPT ERROR`/`Parse Error`/`Invalid call` lines, and an allowlist that REQUIRES a
      written reason (`tools/probe/script_error_allowlist.txt`). A probe that prints an error aborts
      before its `quit()` and hangs; the runner kills it 12 s after the error instead of waiting out
      the timeout. Self-tested with a probe that prints PASS and exits 0 over a script error (fails)
      and one with no verdict (fails). (2) **`shots.py` now keeps the server log and exits 3 on any
      script error in either log**, whatever the screenshots look like. (3) **`release.sh` runs
      `probe_run.py --smoke` (12 probes) before building anything**; a failure stops the release.
      **Not retired, and cannot be from here:** a script error in a code path NO probe or capture
      exercises. The live server still cannot self-report. Coverage is the remaining lever - see the
      sweep result below.
      **SWEEP OF ALL 340 PROBES (run once, 2026-10-13, strict runner): 227 clean, 113 NOT green.
      Measured, NOT triaged - none of the 113 has been confirmed as a game bug.**
      - **9 print script errors** (`dungeon_rank_uniques`, `figure_stands_on_tile`, `gear_gap`,
        `items_in_combat`, `light_samples`, `overworld_compose_cost`, `party_flock_chain`,
        `xp_one_sum`, `dungeon_party_combat`'s own FAIL aside). Read: they are PROBE ROT or harness
        gaps, not game faults - a call to `generate_equipment`, which no longer exists; a bare
        server missing `persistence`/the hotspot table (`get_visible_corpses`/`get_hotspot_at` on
        nil); two probe scripts that no longer PARSE (`items_in_combat` stub signature,
        `overworld_compose_cost` array literal). Cheap to fix; each is worth reading once.
      - **29 report their own FAIL** and exit 1 - a suite nobody has been running. Could be stale
        expectations after refactors OR real regressions; that is the open question and the reason
        this is worth a session: `a_phantom_level_is_not_an_overworld_level`, `card_instances`,
        `companion_lines_are_marked`, `companion_trail`, `danger_step_guard`, `depleted_looks_spent`,
        `dungeon_index`, `dungeon_instance_match` (known stale call-site count), `dungeon_placement`,
        `dungeon_redraw_guard`, `dungeon_variety`, `empowered_hover`, `engine_ramp`,
        `escort_walks_around_danger`, `gatherable_clusters`, `help_topics`, `hover_reachable`,
        `inventory_pressure_and_autosalvage`, `launcher_selfupdate`, `map_payload`,
        `map_payload_golden`, `overworld_render`, `overworld_toggle`, `party_confirm`, `power_rank`,
        `quest_grade_advertised`, `sanctuary_room`, `stat_claims`, `ui_glyph_coverage`.
      - **74 print no verdict line the runner recognises** (probably fine, just a different format -
        the runner's `PASS_RE` needs widening or those probes need a PASS line) and 1 exits non-zero
        with no FAIL text (`ui_scale_1080p`).
      **TRIAGE OF THE 29 REAL FAILS (2026-10-13) - DONE. Result: ZERO regressions from the session's
      own changes; 2 REAL player-visible issues; 1 unclear; 1 not failing; 25 are probe-side.**
      Five parallel read-only investigations, each judging stale/regression/probe-bug with git
      history; I re-verified the claims that carry a decision (counts, clamp values, line endings,
      glyph, the `escorted` path) against the code myself.
      **REAL (fix in the game, small, needs a client release):**
      - **`stat_claims` - player-facing help text is wrong.** Solo fights clamp monster initiative
        at 5-**75**% (`combat_manager.gd:2213`, since the 2026-09-13 stance work: Travelling adds a
        surprise bonus) but two help texts still say "max 55%" (`client.gd` ~40764 and ~41171; the
        second also omits the stance modifier). The PARTY-fight path (`combat_manager.gd:13029`)
        clamps 5-55 with no stance bonus at all - so solo and party fights now disagree with each
        other too. Decide which is intended, then make the text and the probe say it.
      - **`ui_glyph_coverage` - `combat_scene_panel.gd:595` uses an astral glyph** (`"📖 Know This
        Foe"`, added in fcdd7c72) against the project's own "every control label is BMP" rule. The
        claim that it renders as a blank box on Linux is PLAUSIBLE, NOT confirmed. Swap for a BMP glyph.
      **LOW-SEVERITY FINDING (not a probe failure):** `handle_move` reads `escorted` from the
      INCOMING MESSAGE (`server.gd` ~5554, 5629), so a modified client can send `escorted: true` and
      skip the danger-step confirmation. It only skips a speed bump (an honest client clears it by
      stepping twice), but it is client-trusted input on a safety check. Fix: honour it only for the
      server's own calls (46467, 46550), e.g. strip it from network messages in the dispatcher.
      **UNCLEAR:** `gatherable_clusters` (a statistical check on the saved world seed: 34 of 80 large
      stands are single-resource, needs a majority) - could be the seed, touching stands merging
      after the roads/patches work, or a real regression in `_gather_cluster_at`; effect on play is
      minor either way. Needs a fixed-seed re-run.
      **NOT FAILING:** `launcher_selfupdate` passed 5/5 on re-run; most likely it ran in the window
      when the v0.9.834 bump had changed VERSION.txt before the manifest was regenerated (guess,
      unconfirmed).
      **PROBE-SIDE (25) - each is a one-line-class fix, none touched yet except the first:**
      - *Line endings (7):* `a_phantom_level_is_not_an_overworld_level` (**FIXED** - escaped `

- [x] **FIRST BATCH OF BOSS TELEGRAPHS — DONE 2026-09-19.** Five converted: `aerial_dive`,
      `labyrinth_charge`, `tremor_stomp`, `titan_earthquake` (wind-up + resolve) and
      `vorpal_strike` (it multiplies the NORMAL attack, so it was already mitigable and only
      lacked the warning). Each now announces on the round it used to land, resolves on the next
      monster turn, and is answerable three ways: **brace/card mitigates** (20->11, 24->13, 15->12,
      13->11 measured), **stun cancels outright** (0 damage, all four), **or kill it**.
      Riders travel with the blow, so answering denies them too - Tremor's stagger and the Titan's
      hardening stack used to land unconditionally even on a perfect read.
      **A telegraphed burst reads ACTIVE defence only** (`_mitigate_burst`), not armour or CON:
      you cannot out-gear a boss's signature blow, but you can answer it on the turn it is coming.
      Probe: `a_telegraph_is_answerable.gd`.

- [x] **(superseded — the live entry is the one above)** the boss telegraphs themselves. 19 cyclical boss bursts fire the instant the
      round counter hits (`combat.round % N == 0`) with the message printed AFTER the damage - a
      receipt, not a warning. Two constants describe themselves as "telegraphed" and neither is.
      That violates the design's own constraint #4 in `docs/design/dungeon_revamp.md`: *"a
      telegraphed hit only lands next turn unless the player responds... NO unavoidable damage."*
      Now unblocked, because every class finally has an answer. Shape: split each burst into a
      wind-up round (announce, boss spends its turn) and a resolve round answerable by brace
      (mitigate), a defensive card (mitigate harder), CC (cancel) or burst (race).
      **Do the two that already claim to telegraph plus the heaviest hitters first**, behind a
      probe that fails on any burst landing without a wind-up, then convert the rest.

- [x] **BALANCE BATCH: Brace — CARRIED THROUGH THE 2026-09-19 CHAIN RUN.** A player-power change in EVERY fight, not just boss fights
      (owner: *"I'm also fine with r being available outside of boss battles"*). A universal 40%
      mitigation option changes win rates across the board, so `reference_monster_curve.json` is
      stale for it. Do NOT run the chain for this alone - it joins whatever the live death data
      says after a week, per the note below.

- [x] Raw BBCode dumped on screen. The multi-line blow-by-blow was in a `[url=]` ATTRIBUTE, and a
      BBCode attribute cannot contain newlines, so the tag never closed. Keyed `_log_detail` now.

- [x] The card name vanished. `reset_round_summary()` cleared `_player_action_name`, but the round
      divider arrives AFTER the player acts and BEFORE the action lines, wiping it every round.

- [x] Only the actor's name was hoverable. *"I can't hover the 106."* Whole line is the target.

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

- [x] Hover details unreachable from the log PANEL. It got `meta_clicked` and no hover wiring, so
      the links rendered and could not be used. Both halves wired, guarded by the probe.

- [x] Companion skipped round 1 against a Harpy. The Harpy is **Ethereal**; that 33% dodge branch
      returned before the companion acted. An ordinary miss already fell through, which is why this
      was the one case that looked broken. Owner's call: the companion acts when the PLAYER misses
      or is dodged, and still loses its turn to webbed / lulled / charmed / madness.

- [x] **THE CHAIN WAS MEASURING A GAME NOBODY PLAYS** (2026-09-19, shipped v0.9.816). Four
      instrument faults, each hiding the next, all found off the owner's question *"are we sure the
      sim is using the actual starting decks each class is using?"* (the decks were fine):
        1. gear rarity sampled the DROP table per slot - 57% common modelled vs 87% live
        2. `average` handed CLASS KIT (Hoarder-only drops) to level-2 reference players
        3. the curve-writing sampler fled every losing fight, so DEATH read 0.0% everywhere
        4. **`_inject_curve` disarmed the lazy loader**, so `species_power` and `role_multipliers`
           were never read during a refcal run. It fitted AND self-verified without them, then
           wrote a file preserving them - L10 verified at 85% and measured 63% everywhere else.
           Long-standing: the WRITE side of this was fixed when species_power was found to be
           wiped; the READ side was not.
        5. the monotonic clamp ran on the BASE curve, discarding the calibrator's own corrections
           (L5 str 18 -> 54, L10 27 -> 54) - the documented smoothing bug's other half. Now
           clamped on the EFFECTIVE curve (base x mean species multiplier).
      Result: every anchor within +-11pp of target (only L5 exceeds +-10, at -11), death 0.9-6.8%
      against a live 1.81%, and refcal's verify now agrees with independent reads to 1-4pp.
      **Deaths per encounter is now an external target** read off the live server (50 deaths /
      2766 encounters) via `flee_rate_matches_live.gd` - the chain finally answers to something
      outside itself.

- [x] **THE REFERENCE PLAYER WAS STRONGER THAN ANY REAL ONE** (2026-09-18) - *fixed, and it
      invalidates every balance number measured before it.* Owner asked *"are we sure the sim is
      using the actual starting decks each class is using?"* The decks were right; the BODY was not.
      Two independent over-models, both measured against the live server:
        1. `_roll_slot_rarity` sampled the DROP table once per slot, modelling a player who had
           already found a suitable item for all seven. Live L1-4 characters wear **87% common**;
           the model produced 57%.
        2. `average` handed every reference player 1-2 pieces of **class kit** - gear that drops
           only from Hoarder monsters (Minotaur / Wraith / Mimic). Live L1-9 gear is item level
           1.2-2.9 with no class kit in it at all. Now gated to L15+.
      Net: the L1 reference player fell from **189 to ~150 maxHP** and `hp_bonus` per kit from
      **48.0 to 24.6** against a live mean of 22.6. `preflight` now reads **63-68% win at L10**
      where `speciescal` had been measuring **100%** - which is why `species_power` had ratcheted
      43% of its cells onto the x2.50 ceiling.
      **Also retracted:** *"40 of 50 deaths are at L1-9, so low levels are over-tuned."* 83% of
      LIVING characters are at L1-9 too - deaths are proportional to population and carry no
      signal about difficulty. Counting one side of a ratio, the same error as the 3.8x below.
      Probes: `gear_model_matches_live.gd`, `reference_player_is_a_real_player.gd`,
      `sim_plays_the_real_deck.gd`. Fitted to the DYING population (5.2 slots) rather than the
      living one (0.8 slots) because that is the population actually in combat; named in the
      source so the choice is visible.
      **RETRACTED in the same pass:** the earlier claim that plain monsters spawn at *3.8x the
      reference curve*. Running the generator gives **1.4x**. The 3.8x came from dividing live
      death records by a level-only curve, ignoring species variance and over-levelled encounters.

- [x] **One specialist recipe per trade dropped to skill 2-3** (2026-09-18, owner: *"yes drop some
      early recipes to lower skill"*). Measured first: of 109 specialist recipes only **2** sat at
      skill 1-10, so the commission route was unreachable for the first ~15 levels of a trade.
      Self Repair 15→3, Transmute Ore Up 15→3, Disenchant Item 15→3, Craft Fine Parchment 15→3,
      Wooden Door 5→2, Small Enclosure Kit 8→5. **Every one is a utility or a material, never gear
      or a combat consumable**, so this changes WHEN a service is available and not how strong
      anyone is - listed so a future refit sees it, not as a debt on its own.

- [x] **`species_power` SATURATION — CAUSE FOUND AND FIXED, CHAIN RE-RUN 2026-09-19.** It was never
      the clamp. `speciescal`'s own sampler (`_species_win_at`) modelled a DIFFERENT PLAYER from the
      mix it compared against: three classes chosen for strength, never retreating, judged against
      nine classes that flee. Measured on identical monsters: **+24pp at L5, +12pp at L10, +18pp at
      L50**. Every species therefore measured "too easy" and was strengthened, and the ceiling did
      the rest. Both samplers now share a player model; residual gap **4pp**.
      **The re-run proves it:**

          before          after
          136 corrections 134
          68 at ceiling   13   (50% -> 9%)
          0 weakenings     5

      A calibrator that only ever pushes one way is not measuring a difference. It now corrects in
      both directions, which is what the fix predicted and the reason not to widen the clamp.
      **L5 also fixed itself** - 79% against a 90% target became 85%, so the one anchor outside
      tolerance last night was this bias, not a wrong target.
      ⚡ **The fix sat inert in the repo for two releases** (v0.9.817, v0.9.818) because it was
      committed without re-running the chain that writes `species_power`. Owner caught it.

- [x] **(superseded) `species_power` SATURATES - its x2.50 clamp is narrower than the real spread.** 68 of 136
      cells sit on the ceiling (2026-09-19), across three separate runs and on three different base
      curves - INCLUDING after the `_inject_curve` two-worlds bug was fixed, which was the obvious
      suspect - so it is structural rather than an artifact. The cause is visible in the
      data: at L50 the spawn mix wins 33% while Zombie wins 96%, Harpy 91% and Gnoll 80% - the
      average is dragged down by a few brutal species, and no single multiplier range can pull the
      easy ones onto a mix defined by the hard ones. The sim's own comment already names it:
      *"Jabberwock wins 16% and Demon Lord 82% on near-identical stat lines."*
      **This is a design question, not a tuning one** - either the clamp widens (and a Giant Rat at
      L50 becomes genuinely dangerous), or the brutal outliers get pulled down by hand, or species
      variety at high level is accepted as wider than the band. Deliberately NOT widened quietly:
      saturation is not convergence, and a clamp that binds on half its cells is reporting that the
      model is the wrong shape. Owner's call.

- [x] **`assassinate_pct` reaches the dice** (v0.9.790). Carried through the v0.9.816 chain. Silver Tongue +15% and one unique now work
      as written - a small per-class gain for the Trickster line. Glance at it on the next `refcal`.

- [x] **The companion acts through an ethereal dodge** (v0.9.803). Carried through the v0.9.816 chain. Owner waived re-calibration for
      it as too narrow to matter (Ethereal monsters, 33% of attacks). Listed so that if the batch
      runs anyway it is measured rather than forgotten - not as a debt on its own.

- [x] **Crafted gear and enchanting were re-sized to the drop curve** (2026-09-18). Carried through the v0.9.816 chain. The crafted +
      runed PAIR moved from ~0.5x a drop to **1.15x**, and the per-item enchantment ceiling now
      scales with level instead of being flat. The reference player has never carried crafted gear,
      so the chain has never seen this - and gear is one of the things it is most sensitive to.
      Re-measure with `crafted_pair_worth.gd` after any drop-table change, since the target is
      derived from the drop generator and moves with it.

- [x] **Knight +15% damage and Mentee +50% XP now reach the dice** (2026-09-18). Carried through the v0.9.816 chain. Both were dead
      when the curve was last fitted, so the reference player has never carried either. Rare
      endgame titles only, so the effect on the aggregate should be small - but the Knight damage
      bonus lands in `calculate_damage` beside the gear multiplier, which is a path the chain does
      measure. Glance at it on the next `refcal`.

- [x] **The high-level win targets predate retreat.** **SETTLED 2026-09-19.** Owner chose "fix the
      high end only": leave the on-ramp where it is and pull L50+ up toward target. That turned out
      to be what `DIFFICULTY_RAMP` already encodes (92% at L1 ramping to 58% at L10000) - I had
      wrongly described the target as a flat 60% and built an option menu on it. No new knob was
      needed; the v0.9.816 refit does exactly this.

- [x] **(superseded — settled 2026-09-19, see the ticked entry above)** The high-level win targets predate retreat. 60% was chosen when a "loss" meant a death;
      it now mostly means a retreat. Revisit alongside the Unburied, since extra lives change what
      survival means. This is a question about the TARGET, so settle it before a chain run rather
      than after. (Moved here, 2026-09-18.)

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

- [x] **The dungeon LIST** sent the TYPE'S letter beside the INSTANCE'S number, so the label was
      assembled out of two different dungeons - while the `display_name` on the same row already
      used the instance's. Half of one row disagreeing with the other half.

- [x] **The entry warning** (new this session, so this one was mine).

- [x] **The compass bearing.** Now names the full label rather than a grade: it points at ONE
      dungeon, so it knows the rank.

- [x] **The Atlas**, all three rows. A dungeon TYPE has no single grade to report, so the Atlas
      now shows the grade of the one THIS player found - the record stores it at discovery, and
      `note_dungeon_discovery` gained a `rank` so it can keep both halves.

- [x] GM dungeon entry read `(T3)` — the line the owner saw.

- [x] The compass bearing read `(T5)`.

- [x] The Atlas SPOTTED row printed a bare `2` — an int interpolated straight through a `%s`.

- [x] The Atlas DISCOVERED row rendered a bare letter with no colour and no hover, against
      PowerRank's own standing rule (*"Never render a bare label"*).

- [x] The Atlas RUMOURED row said "a Tier G dungeon".

- [x] The dungeon LIST and the ENTRANCE panel both fell back to "Tier G" when no instance exists.

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

- [x] **Starting copies are already correct.** All nine classes: 5 cards, 5 copies, no duplicates.
      The earlier fix the owner remembered is `repair_deck_once()` (commit `3ac2e08c`), which
      repaired deck SIZE on live saves (6-13 cards against a designed 5) — a different number.

- [x] **Use tracking is already per-instance.** Proven both ways: a cast addressed by instance id
      (`record_mastery_use(hand_key)`, which is what combat does) and a bare-name cast while the
      active instance is announced. Both land on the copy, neither on the shared card name.

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

- [x] **The Warden's handout is named like endgame loot** — **DONE 2026-09-17.** *"Rusty Weapon
      of Wisdom"* is *"Rusty Weapon"*, and the kit is deterministic instead of a fresh roll per
      character. The `plain` path in `_generate_item` this entry asked for exists; the level moved
      5 → 10 to pay for the dropped affix, measured at 1.04x of the old kit's power.
      ⛑ **AND THIS WAS THE SAME JOB AS "THE STARTER KIT IS STILL NAMED LIKE ENDGAME LOOT"**, filed
      separately under another name — same function (`get_starter_kit_item`), same cause, same
      requested fix, two open lines. Exactly what the backlog rule at the top of CLAUDE.md is for.
      Full write-up under that heading; probe `tools/probe/starter_kit_plain.gd`.

- [x] **Party kills never credited a kill quest.** `_end_party_combat_all` never called
      `check_kill_quest_progress` / `record_monster_kill` / the bestiary. Affected ALL co-op, not
      just the tutorial — the tracker sat at 0/1 after the wolf died.

- [x] **A re-bake never reached the screen.** Godot only re-imports on an editor pass; the bake
      script now reports which files the game will still draw stale.

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

- [x] **WHO IS ONLINE — DONE. Discord half is LIVE and verified.** Owner: *"a tool that is
      efficient and doesn't use much data that shows the players currently online...
      viewable from my android phone and in discord."* The server EDITS one Discord message
      every 3 minutes (name, level, class, where), self-heals if that message is deleted,
      and logs every failure. `docs/status.html` is the web half, linked from every page,
      reading a public gist. **Owner input needed:** a gist-scoped GitHub token for the
      server to write with - the `gh` CLI token would work but carries full repo scope,
      which should not sit on a game server.

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

- [x] Assassinate read "~1 · 3% kill" in the Warden fight. The party payload hand-copied the engine
      fields and lacked 11 of them (finisher kind/damage, read_note, ramp, all three meter LABELS).
      Both paths now read `engine_display_fields`.

- [x] Wild Swing whiff read as "Meteor - 1 damage" with no miss line (13/60 casts). Now announced.

- [x] The card PREVIEW cast the upgrades: Opener and Sure Strike consumed at fight start, Sacrificial
      spent by the quote (every real cast 0), Wild Swing's quote flickering to 0. Preview is pure now.

- [x] Partial-cast damage pip quoted a full spend while the effect line quoted the planned one.

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

- [x] **DONE v0.9.778 — restored on the `[url=]` mechanism.** **OPEN, and taken out by this fix: map hover and click-to-inspect for players and
      companions.** The overlay that was stood down also carried them. The mechanism to restore
      it already exists and is proven - the dungeon-entrance hover wraps a map cell in `[url=]`
      and the payload carries what it needs. Same shape, for `!other` cells and the figure that
      stands on them.

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

- [x] **DONE 2026-09-11 — Tier LEVEL bands: one source.** It was EIGHT copies, not three: the seven typed-out ladders (monster_database x2, combat_manager, quest_database, quest_manager, server x3) now all read `PowerRank.tier_for_level`, and the dungeon table is `PowerRank.dungeon_band()` = monster band + a named `DUNGEON_REACH` (7/7/10/10/20, zero from tier 6). Numbers unchanged: probe `tier_bands.gd` holds all 81 dungeon rank slices and all seven consumers to the old values at 37 levels; re-injecting a wrong reach fails 2. Was: three copies exist today:
      `monster_database._get_tier_info` (hard-coded thresholds), `quest_database.TIER_LEVEL_RANGES`
      (the same bands as a table) and `dungeon_database.TIER_LEVEL_RANGES` (wider below tier 6:
      1-12 / 6-22 / 16-40 / 31-60 / 51-120 against 1-5 / 6-15 / 16-30 / 31-50 / 51-100). Move
      the canonical bands into `shared/power_rank.gd` beside the ladder, make the two monster/quest
      copies read it, and express the dungeon table as base band + a named `reach` per tier so
      the numbers a dungeon uses today do not move. A probe asserts all three agree with the one
      source and that every dungeon band is identical to before.

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

- [x] **DONE 2026-09-10 - private art backup exists.**
      <https://github.com/Dextobust33/Phantom-Badlands-Art> (private, 1,849 files) holds every
      path in `tools/licensed_assets.manifest` plus the 20 untouched purchased Raven `.zip`
      files. Verified by MD5 against the working tree - 0 missing, 0 differing - and by an
      actual RESTORE DRILL: `prop_floor32` deleted, gate went red and named it, restored from
      the repo by the documented command, gate went green, occlusion probe passed. A backup that
      has never been restored from is a hope, not a backup.
      Risks accepted knowingly and written down in `docs/ASSET_LICENCES.md`: a private repo is
      one click from public, and it stores plaintext on a third party.

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

- [x] **PHASE 2 SCOPE — what "sprite the overworld" has to cover. SATISFIED (audited 2026-09-19).**
      Checked on disk rather than assumed: **all fourteen gatherables the item names have sprites**
      - tree, stone, ore_vein, dense_brush, herb, flower, mushroom, bush, reed, cactus, ice_bloom,
      swamp_lily, mountain_herb, brambleberry. Wilderness tiles, roads, water and structures
      shipped with the overworld art pass (113 images, gated on a pixel fingerprint so they cannot
      silently go stale). Original scope (2026-09-11, after the
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

- [x] **SUPERSEDED — the shader route shipped in v0.9.768, so the baked-dim alternative is moot. Cheaper atmosphere worth considering before any shader:** the compositor can already bake
      per-cell variants, so a DIM version of a floor tile is a cached texture rather than a shader
      pass. That is how the existing occlusion and decor work; it would not need a shader at all,
      at the cost of more cache entries. Worth comparing before reaching for GPU work.

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

- [x] **Dungeon level mismatch — RESOLVED, confirmed by the owner 2026-09-18.** Was blocked on a
      second example that never came; the grade-follows-the-land work in v0.9.802-803 covers it.

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

- [✗] **~~"Party play isn't working properly"~~ — WITHDRAWN 2026-09-18.** Owner: *"an old report
      that's no longer valid and can be removed."* It sat since 2026-08-26 with no repro ever
      captured; party combat has been rebuilt several times since.

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

- [x] **⚑ POST SERVICES — TWO OF THREE PARTS DONE (2026-09-19).** Part 1 (the healer's
      dominated options) and part 3 (merchants: speed, stock, and the VISIBILITY fault that was
      the real cause) are shipped and probed. Part 2 (wandering blacksmiths and healers) is filed
      against the LIVING WORLD arc by the owner's own note and waits on nothing here. Three parts.

      1. **The healer has no reason to offer anything but the cheap option.** *"The healer options
         may need looked at as well, there's no real reason to do anything other than a quick heal
         for reviving companions."* So the expensive options are dominated - measure what each
         costs and gives before redesigning, because "dominated" is a claim about the numbers.
         ✅ **MEASURED 2026-09-18 and the owner is right: Full Heal costs 1.02x the same healing
         bought as Quick Heals, at EVERY level.** It is not close, and it is not level-dependent -
         the expensive option is strictly dominated by spamming the cheap one, so there is no
         decision at the healer at all. `tools/probe/healer_options_are_a_choice.gd` FAILS on this
         today. **The fix is not designed** - this is the only post-service part left, the
         measurement is already done, and it does not depend on anything else. Cheapest real work
         on the list.
      2. **Wandering blacksmiths and healers** - *"we may want to add in wandering blacksmiths and
         healers when we do the living world arc."* Filed against that arc rather than here.
      3. **Merchants move too slowly and are empty when you meet them — MEASURED 2026-09-18, and
         both halves are real.** *"Current merchants also move way too slow from post to post and
         seem to pretty much never have anything for sale when you see them out and around."*

         * **Speed: `MERCHANT_SPEED = 0.025` tiles per second - one tile every FORTY SECONDS.**
           A hundred-tile leg between two posts takes over an hour of real time. Relative to a
           player, who moves a tile per keypress, a merchant is very nearly stationary.
         * **Stock: a road merchant has NO inventory of its own.** `_flatten_carried_to_shop_items`
           builds its shop entirely from **carried market LISTINGS** - things other players have
           listed, which the courier is moving between posts. There is an explicit
           *"The merchant has nothing to sell right now"* branch and **no fallback stock at all**.
           So with a small or quiet player base, a road merchant is empty by construction.

         ⛑ **The two faults compound, which is why it reads as "pointless" rather than "slow".**
         A slow merchant is one you meet rarely; an empty one makes the rare meeting worthless.
         Fixing only the speed would give players more frequent encounters with nothing to buy.

         **✅ BOTH FIXED 2026-09-18 — and the stock half was CORRECTED after the owner read it.**
         My first version called the post shop generator with `character.level`, which returns
         **4-12 items scaled to the buyer** - a full market stall on every courier, stocked to
         whatever the player happened to need. Owner: *"We don't want players to just be able to
         buy all of their gear upgrades from a wandering merchant for cheap and trivialize the
         drops and crafting work."* It would have done exactly that.
         Now three constraints, one per clause of that note: **consumables only** (equipment on a
         courier comes solely from carried player listings, so the gear economy stays
         player-driven), **the AREA's level not the player's** (`get_post_anchored_level`, the same
         function the land grade reads), and **at most 3 items at the road markup**. A belt-and-
         braces `_is_equipment_item` guard refuses gear whatever the generator returns, because
         "a courier sells no gear" is an economy decision and belongs where it is stated rather
         than trusted to a specialty string two thousand lines away.
         Carried player listings still come FIRST - they are the reason to stop a courier - with
         the small consumable stock beneath, and "nothing to sell" now requires BOTH to be empty. `MERCHANT_SPEED` 0.025 → **0.25**.
         ⛑ **The speed was sized against `MERCHANT_REST_TIME`, not measured**, because the road
         graph needs world generation and `compute_merchant_circuits` returns nothing headless. A
         200-tile leg is now **13 minutes against a 5-minute rest (2.7x)** where it was over two
         hours (25x+). The honest claim is that the RATIO is sane now, not that 13 minutes is the
         right number - **it wants a live check.**
         Probe: `tools/probe/road_merchant_stock.gd`, which asserts the ratio rather than the
         constant, so a future route change that lengthens legs still reads correctly.

         ⚡ **THE LIVE CHECK HAPPENED 2026-09-19, AND FOUND A THIRD FAULT THIS MISSED.** Owner:
         *"I didn't see any last time I was on the live server."* Neither speed nor stock was the
         binding problem - `_refresh_merchant_cache` dropped any merchant RESTING AT A POST with a
         bare `continue`, so it did not draw, `is_merchant_at` was false and `get_merchant_at`
         returned nothing. Standing at a post you met one **0% of the time**, at any road length;
         walking a road, 5-18%. The economy worked throughout (the live log is full of couriers
         hauling stock) - the courier was simply a ghost wherever players actually stand.
         Now parked on the first road tile OUTSIDE the post, off the station art. Probe
         `merchant_is_findable.gd`, proven to fire. **Server-side - needs a deploy to reach live.**
         The lesson worth keeping: two fixes were measured and shipped for a complaint whose cause
         was neither of them, because nobody checked that the thing was VISIBLE before tuning how
         fast it moved and what it carried.
         ⛑ Still open and NOT addressed here: the POST side - see *"Merchant / market-house
         balancing"* (Sun Keep's market near-empty). This fix gives couriers a floor; it does not
         tell us whether post markets have a supply problem of their own.

         ~~Shape of the fix:~~ give road merchants their OWN generated stock as a floor - the post
         merchants already have `generate_shop_inventory(player_level, seed, specialty)` - and keep
         carried listings on top as the interesting half, since those are real player goods at a
         convenience markup. Then raise the speed, which also makes the market more responsive
         because couriers ARE the market's logistics.
         ⛑ Check against the known *"Merchant / market-house balancing"* item (Sun Keep's market
         near-empty, 3 shrine items) - that is the POST side of what may be one supply problem.

- [x] **Launcher revamp + feedback inbox — DONE (found 2026-09-19 by hand-checking the audit's
      blind-spot list).** The launcher self-updates: `LAUNCHER_VERSION = "2.5"` compared against
      the manifest's `launcher_version`, which `tools/make_client_manifest.py` generates so the
      field cannot go missing again. The feedback inbox shipped in v0.9.728 - in-game
      "Suggest an Idea" / "Report an Issue" posting to a Discord webhook.
      ⚡ This named no probe, symbol or completion word, so the audit could not see it - it was
      found because the audit LISTED it as unverifiable and a human grepped. That is the blind-spot
      half of the process working, and the fifth already-built item found on 2026-09-19.

- [x] **AN UPGRADED CARD SHOULD LOOK UPGRADED — owner 2026-09-04. COMPLETE 2026-09-19.** All
      three sub-items are done: the hover preview, the damage estimate (fixed once its real cause
      — card gear, not milestone picks — was found), and now **the card itself**.
      *"Upgrading a card and then the card looking exactly the same and the description being
      exactly the same sucks."* Listing upgrades in the description shipped; that is the floor.
      - [x] **Preview on the pick screen. DONE** — `_ms_preview_panel` in client.gd, *"hover: the
        card as it would read once upgraded"*. Verified in code 2026-09-19.
      - [~] ~~Preview on the pick screen.~~ Hovering an upgrade shows YOUR card with it applied -
            *"if I'm upgrading Analyze and I hover over a Mending upgrade it should show my Analyze
            card with the Mending effect"* - and hovering that preview shows what it would then do,
            all before committing.
      - [x] **DONE 2026-09-19 — THE CARD ITSELF CHANGES.** An upgraded card carries a **heavier
            frame**, a gilded **✦ / ✦✦ / ✦✦✦ sigil** on its banner, and **lit art**, in the combat
            hand and the deck screen. Three steps, not one per upgrade: a card can carry six and
            six distinguishable frame weights is noise, not information. Named on hover —
            **Honed / Tempered / Ascendant**.
            ⚑ **ONE TABLE** (`CardUpgrades.card_upgrade_look`), because the deck screen and the
            combat hand are precisely the pair this codebase keeps finding drifted (the action
            bar's own name table, the combat log styling by literal word, the buff panel's third
            copy). A card that looks invested-in while you build your deck and plain the moment
            it reaches your hand is the same bug wearing a new hat.
            ⛑ **It does NOT touch the border colour**, which already carries the ability category
            AND whether you can afford the card. A third meaning there would have made an
            unaffordable card and an un-upgraded one read alike — worse than the bug being fixed.
            ⛑ **Per COPY** in the hand and in the deck's copy rows, since duplicates level
            independently: a three-times-upgraded Cleave and a fresh one were two identical rows.
            Probes: `an_upgraded_card_looks_upgraded.gd` (wiring, both surfaces, proven to fire
            twice) **and `the_upgrade_sigil_reaches_pixels.gd`**, which lays a real card out in a
            real window — because a source-reading probe cannot tell whether a badge is visible,
            and a figure block in an unreachable branch shipped TWICE here before anyone noticed.
            Measured: sigil 32x19 on the banner, inside the card's clip rect, name still 84px.
      - [x] **The estimate must follow. DONE 2026-09-19 — and the stated cause was WRONG.** This
            line said the fault was that it "counts only `power` picks". It is not: the server's
            `get_tier_effect_mult` counts only power picks too, so that half always agreed.
            The real gap was **`get_skill_damage_bonus`** — card TOMES plus card-specific GEAR
            (`card_gear.gd`) — a percentage the server applies to every hit and the face never
            showed. Measured: equipping one `card_power_ambush` item moves the server's bonus
            0% → 25% and moved the card face not at all. Worst possible moment to under-report,
            since it is exactly when a player has just farmed the thing.
            Also fixed: the client hardcoded `0.02` / `0.12` where Character has `TIER_POWER_PER`
            and `MILESTONE_POWER_PER` — correct that day, and a silent liar the day either moves.
            Probe: `the_card_face_counts_your_gear.gd`.
      **Groundwork exists:** `card_upgrades.gd` carries `name` + `desc` per upgrade,
      `_ability_desc_bbcode` is the single description builder, and the hand cell and deck card are
      both built from one `build_deck_card` path. A preview is composition, not new plumbing.

- [x] **MAGIC BOLT — DUPLICATE of an item already RESOLVED 2026-09-07** (see the ticked
      "Magic Bolt damage vs investment" entry earlier in this file, closed by the `magecost`
      audit at n=40). This copy was added so an archive sweep would read complete, and then
      outlived the original - the Dungeon Atlas pattern exactly. Audited 2026-09-19.

- [x] **⚑ INVENTORY BLOAT — SUBSTANTIALLY RESOLVED (2026-09-19).** Part 3 (auto-salvage) is
      done twice over: the consequence preview, then the keep-rule moved from affix NAMES to
      STATS, which is what made the owner's own example expressible. Part 2 (tools) was mostly
      built already - a broken tool auto-equips your best spare. Part 1 (a pouch) is filed with a
      MEASURED trigger that has not fired: fullest live character 28/40 against ~32. **Part 2's
      last gap — showing SPARE COUNTS before a tool breaks — closed 2026-09-19.** Three
      complaints, one disease: the player's bag fills with things they did not choose and cannot
      triage.

      1. **Consumables and tools eat backpack slots.** *"Items and tools can buildup and takeover
         your backpack slots. We may want to have a separate item pouch or unlimited items."*
      2. **Tools specifically are a chore — MOSTLY ALREADY BUILT (audited 2026-09-19).** *"They are
         currently a pain to have to go back and craft and then they take up an inventory slot,
         it's hard to tell if you have backups etc."*
         ✅ **A broken tool already auto-equips your best spare.** `_auto_equip_tool_replacement`
         finds the highest-tier intact tool of that subtype, equips it, and the `tool_broken`
         message names the replacement and its durability - the no-spare case included. So "go
         back and craft" is already not a trip you have to make mid-run.
         ✅ **DONE 2026-09-19 — THE TOOLS PANEL NOW SHOWS YOUR BACKUPS.** Each slot reads
         `⛏ Pickaxe T2  14/20  (2 spares)`, and a tool at or below **half durability with nothing
         behind it** says `(no spare)` in orange — the moment it is worth going to make another.
         A fresh tool with no spare says nothing, because that is not news.
         ⚑ **The count and the replacement are ONE rule**, `Character.tool_spares`: the server's
         `_auto_equip_tool_replacement` was a local loop and now picks from it too. A panel
         counting spares by its own rule is the "one value, two places" shape, and the failure
         would have been specific and nasty — the panel promising a backup the game will not
         reach for, so a player sets out on a gathering run believing they are covered. A
         **broken** tool in the pack is not a spare (it is the thing being replaced).
         Probe: `the_panel_counts_the_spare_you_get.gd`, proven to fire on both halves.
         ⛑ **And it does not cost the map a row.** The suffix goes into a 240px box at font 13 —
         about thirty characters, genuinely close — and a wrapped Tools line makes that block
         taller, with every row it gains coming out of the ASCII map. MEASURED at 1080p against
         the same panel with the suffix suppressed: 9 rows either way, 162px in a 180px box.
         Release gate check `tools_panel_no_wrap`, proven to fire by lengthening the suffix
         (10 rows, box 180→198).
         ⚡ I proposed BUILDING the auto-equip on 2026-09-19 and the owner said it likely already
         existed. It did. Fourth already-built thing proposed that day - the reason
         `tools/backlog_audit.py` now exists.
      3. **✅ DONE 2026-09-19 — THE KEEP RULE NOW KEEPS STATS, NOT AFFIX NAMES.** The owner's own
         example was not expressible: the rule matched `prefix_name`/`suffix_name`, and MEASURED,
         every stat has more affix names than the 5-per-stat cap allowed — **hp_bonus 15,
         attack_bonus 16, defense_bonus 15, wits_bonus 6**. So "keep HP and Wits" meant ticking 21
         names against a cap that covered 10, and a player who configured it as carefully as the
         screen permitted still lost two thirds of their HP gear, **silently**. Wrong UNIT, which
         CLAUDE.md names as "as wrong as a guess and far more convincing".
         Now two selections cover all 21 affixes, and any added later. The cap is gone with the
         names (a stat list is bounded by the stats that exist). Existing filters are **cleared and
         auto-salvage turned OFF** rather than translated — owner's call, because a translated
         filter protects more than was picked and the safe direction for a destructive setting is
         off-until-reconfirmed. Probe: `keep_what_you_asked_to_keep.gd`.
      3b. **(original) Auto-salvage must be understandable and configurable IN the inventory.** *"They should
         be able to understand it and set it up easily so it can autosalvage or autojunk to then be
         listed automatically next time they go to the market. For example lets say they only want
         things that give them an HP and Wit increase, if they can easily set that up then they
         could make it where any equipment they get that isn't an upgrade to both of those gets
         autosalvaged or autojunked without them ever having to manage it."*

      **⛑ The rule the owner described is a KEEP rule, not a junk rule** - "I want HP and Wits" -
      and everything failing it is disposed of. That is the right way round: a junk-list needs
      maintaining forever as new items appear, while a keep-rule covers items that do not exist yet.

      **Check what exists before building:** there is already an auto-salvage path
      (`awaiting_salvage_result`, inventory-full auto-salvage on party reward equipment) and a
      market listing flow. This is likely a RULES + UI job on top of machinery that is already
      there, not a new system - verify first.

      Sits next to the crafting arc because it is the same complaint from the other end: crafting
      asks *"what do I do with these materials"*, this asks *"why do I have all this at all"*.

- [x] **CRAFTING REASSESSMENT — DONE 2026-09-18, ticked 2026-09-19 by audit.** Steps 1 through 9
      are all marked complete below and the item carries no open marker anywhere in its ~950 lines.
      It stayed unticked for a day and was OFFERED TO THE OWNER as available work on 2026-09-19,
      which is what prompted `tools/backlog_audit.py`.
      **(original scope)** scoped by the owner 2026-09-17, and it is most of the system.
      Asked how much of crafting was in scope, the owner answered *"Most of it"*: *"Players gather
      a bunch of materials and don't really have useful things to do with them. It is all too
      difficult to understand for them currently. Ideally they should have clear options that
      obviously benefit them to do. Currently it's a pain to craft and you're often making things
      with no real value or use just to try and level up your crafting skill. I'd say all of the
      craftable items and options need to be reassessed and we need a clear path that speaks to
      the identity of each type of crafter. We want interesting options that are beneficial for
      players rather than grindy crap that no one wants."*

      **☑ STEP 1 DONE 2026-09-18 — FAULT 3 IS MEASURED, and it is the one that had to go first.**
      *"You're often making things with no real value or use"* is testable, and the answer decides
      how much of faults 1, 2 and 4 are really content problems: if crafted gear were competitive,
      the job would be legibility and destination. It is not competitive.

      `tools/probe/crafting_worth.gd` compares all **58 craftable weapons/armour** against gear
      produced by the REAL drop generator at the recipe's own item level (per the equipment rule -
      call the generator, never read the table). **Median crafted item is 0.49x a drop. 40 of 58
      are below 0.80x; only 6 are above 1.25x; p10 is 0.12x.**

      **⛑ AND IT IS TWO DISTINCT FAULTS, WHICH THE AVERAGE HIDES.**

      *Per SLOT* - half the gear is fine and half is nowhere:

      | slot | median vs drop | | slot | median vs drop |
      |---|---|---|---|---|
      | amulet | **1.04x** | | weapon | **0.37x** |
      | armor | **1.04x** | | shield | **0.25x** |
      | helm | 0.81x | | boots | 0.21x |
      | | | | ring | **0.12x** |

      A single "crafting is weak" number would send someone to buff all of it and overshoot the
      half that already works.

      *Per LEVEL* - **erratic, not decaying**, and that distinction changes the fix. Measured:
      0.31x at item level 5, 0.52 at 15, 0.46 at 30, 0.26 at 50, 0.72 at 70, 1.01 at 80, 1.38 at
      90, then 0.27 at 100 and 0.17 at 150. A band where crafting is genuinely good sits between
      two where it collapses. A decay would be corrected with a scaling term; this is what happens
      when recipe stats are **hand-authored constants** and drops are **generated off a level
      curve** - the two can only agree by coincidence, and at 90 they happen to while at 100 they
      happen not to.

      **So the fix for fault 3 is structural, not a pass of number edits:** derive recipe output
      stats from the same curve the drop generator uses, with a deliberate offset per slot, so
      crafted gear holds a known relationship to drops at every level instead of drifting.
      **What that offset should BE is an owner decision** - see the questions below.

      ⛑ The first run of this probe reported *"crafted gear beats drops 52x"* and printed a
      confident verdict under it. A recipe stores `base_stats`; a drop stores `affixes` and has no
      `stats` key, so every drop summed to zero. Fixed before it was believed - and it is the
      reason the probe now names the container it reads.

      **☑ STEP 2 DONE 2026-09-18 — WHERE A MATERIAL GOES, after the owner redirected the arc.**
      Asked to pick a power ratio for crafted gear, the owner declined the question and named the
      real one: *"I want to get rid of a lot of the level gated grindy crafts unless they are for
      something that's actually useful and easy for the players to understand, trade, and use. No
      one wants to sit around and craft a ton of dust, logs, etc... Seems like many materials just
      pile up or players get them and don't care because they don't know what to do with them. May
      be that we have to simplify or categorize them better as well."*

      `tools/probe/crafting_materials_audit.gd`, over **131 materials and 258 recipes**:

      * **9 materials have NO destination at all** - no recipe consumes them and they are not
        edible: `ash_wood`, `darkwood`, `ironwood`, `oak_wood`, `worldtree_branch`, `black_pearl`,
        `freshwater_pearl`, `rock_salt`, `ice_crystal`.
        **⛑ FIVE OF THE NINE ARE WOOD — over half the wood in the game is unusable**, and chopping
        is one of the gathering jobs. That is the owner's *"a ton of dust, logs"* found in the data.
      * **16 more are EDIBLE ONLY** - no recipe wants them, and eating is all there is: 8 of 23
        herbs, 5 of 17 plants, and the single meat type.
      * **17 recipes produce another MATERIAL** rather than anything a player can use - the
        intermediate tier the owner wants gone unless it earns its place.
      * **Gating is heavily back-loaded: 138 of 258 recipes sit above skill 25**, and 72 above 50.
        A player meets the useful half of the book only after grinding the half that is not.

      ⛑ **The first version of this probe reported 25 orphans (19%) and would have pointed the
      redesign at the wrong half of the list.** It did not know that `FOOD_MATERIAL_TYPES` is read
      at three places in `server.gd`, so a herb no recipe consumes can still be eaten. Eating is a
      destination. Checked before reporting rather than after.

      **What this says about the fix:** the material list does not need trimming so much as
      *sorting into destinations*. Three groups fall straight out of the data - materials with a
      real recipe use, materials that are only food, and materials with nothing at all - and the
      third group is small enough (9) to be fixed by giving them uses rather than deleting them.
      The 17 material-making recipes and the 138 recipes gated above skill 25 are where the
      *"grindy"* complaint actually lives.

      **☑ STEP 3 DONE 2026-09-18 — THE IDENTITY PASS, and four of the five already exist.**
      Owner chose *"decide per crafter after the identity pass"* for the cull, so the identities
      come first. Measured from the recipe table rather than invented:

      | crafter | recipes | what it makes today | identity |
      |---|---|---|---|
      | Blacksmithing | 68 | armor 49, **weapon 9**, upgrade 7, reforge 2, self_repair 1 | **gear** — clear |
      | Enchanting | 56 | rune 46, material 6, upgrade 3, disenchant 1 | **runes + improving gear** — clear |
      | Construction | 52 | structure 49, material 3 | **structures** — clear |
      | Alchemy | 38 | consumable 35, transmute 2, extract 1 | **consumables** — clear |
      | Scribing | 44 | scroll 18, tome 7, enhancement 5, material 8, escape 3, map 2, bestiary 1 | **none — seven output types, no majority** |

      **So the identity work is one crafter, not five.** Scribing is the scattered one and the only
      place *"what is this crafter FOR"* has no answer already sitting in the data.
      **And blacksmithing has a hole:** 49 armour recipes against **9 weapons**, and
      `crafting_worth.gd` measures weapons at **0.37x** a drop - the thinnest category is also the
      weakest one, inside the largest crafter.

      **☑ STEP 4 DONE — CONSUMABLES, measured after the owner named them.** Owner: *"there are too
      many of them and with names that make people not sure what they even give (especially in
      combat, you have to hover to try and remember what each of them give in the combat item
      list)."* `tools/probe/consumable_clarity.gd`, over 35 consumable recipes:
      * **19 of 35 cannot be told apart by name alone** - `Potion of Fortitude`, `Elixir of Power`,
        `Potion of Insight`, `Prismatic Elixir`, `Elixir of the Void`, `Elixir of the Abyss`,
        `Primordial Tonic`... The combat item list shows NAMES, which is exactly where it hurts.
      * **13 are the four resource ladders** (health x4, mana / stamina / energy x3 each) and those
        are fine: the name carries both the effect and the grade.
      * So it is **13 clear + 19 opaque + 3 other**. The COUNT is not really the problem; the
        naming is - which matters, because cutting to fix a naming fault would remove content that
        works.

      **☑ AND WHAT QUALITY IS WORTH.** Owner: *"a lot of items that could get quality that didn't
      benefit enough to justify even having it."* Measured: Poor 0.50x, Standard 1.00x, Fine 1.25x,
      Masterwork 1.50x - the whole spread a player can influence is **+50%**, and **Fine to
      Masterwork is +20%**. On a 50 HP potion that is +25 HP and +10 HP. Felt on gear; invisible on
      a flat-restore consumable, which is the complaint in numbers.

      **☑ STEP 5 DONE 2026-09-18 — THE PER-CRAFTER CULL, and it is FAR smaller than 258 suggests.**
      The owner chose *"decide per crafter after the identity pass"*. Done, and three of the five
      turn out to need **no cull at all** - they are systematic LADDERS, not bloat:

      | crafter | shape | verdict |
      |---|---|---|
      | Blacksmithing 68 | **7 slots × 9 item levels**, one recipe each, plus 7 upgrades | **no cull** - fix the STATS |
      | Enchanting 56 | **13 stats × 3 tiers** (Minor/Greater/Supreme) + 7 specials | **no cull** - names already state their effect |
      | Construction 52 | a build kit of 49 distinct structures, **41 at skill ≤25** | ⚠ **owner overrode this - see below** |
      | Alchemy 38 | 13 clear ladder potions + **19 opaque** + 3 | **CULL** - cut most of the 19, rename survivors |
      | Scribing 44 | seven output types, no identity | **CULL to ~6-10** |

      **⚠ CONSTRUCTION — OWNER OVERRODE THE "NO CULL" READING, 2026-09-18.** The data says the 49
      structures are distinct and mostly ungated, which is why I read it as healthy. The owner's
      objection is not about duplication, it is about **effort per piece**: *"I think it takes too
      much investment for a player to want to micromanage each piece. I'm not saying we need to
      remove them but anything that stays within it needs to have a justifiable purpose. We've
      talked about play posts that can be bought with valor and them putting down a completed post
      and that may replace a lot of what construction offers."*
      So the test for a structure is **"would a player place this one deliberately"**, not "is it
      distinct" - and placing 49 things one at a time is the chore, however good each one is.
      ⛑ **This is blocked on PLAYER PHANTOMS**, which is exactly the prefab-post feature described:
      buy a semi-randomised completed post with valor and place it. If that ships, most of
      Construction's reason to exist moves into it, and the cull becomes "what do you still place
      by hand ON a post you already own". **Decide Construction after phantoms, not before.**

      **So the cull is two crafters, not five**, and the other three need their NUMBERS fixed
      (derive output stats from the drop curve) rather than their content deleted. That is a much
      cheaper arc than the recipe count implied, and it protects content that is already working.

      **⛑ AND I HAD TO CORRECT MYSELF ON BLACKSMITHING.** I reported *"49 armour recipes against 9
      weapons - the thinnest category is also the weakest, inside the largest crafter"* and called
      it a hole. It is not: `armor` is an output TYPE covering six slots while `weapon` is one
      slot, so **per slot they are identical** - one recipe per level, and weapons are among the
      most complete rows in the grid (9 of 9 levels; amulet, boots, helm, ring and shield each miss
      level 90). Comparing a category to a slot produced a finding that was not there. The weapon
      problem is entirely POWER (0.37x), not coverage, and the fix is the same stat derivation
      every other slot needs.

      **☑ STEP 6 DONE 2026-09-18 — RUNES ARE WORSE THAN THE GEAR WAS, and they get worse as they
      get grander.** `tools/probe/rune_worth.gd`, comparing each rune's `rune_cap` against the
      median total of a REAL drop at the level that tier is used:

      | tier | rune adds | of the item it sits on |
      |---|---|---|
      | minor | **0.17x** | |
      | greater | **0.06x** | |
      | supreme | **0.03x** | |

      **A Supreme Rune — the top of a 46-recipe block, behind high enchanting skill and expensive
      materials — adds three percent of what the item already carries.** A Minor Rune of Strength
      adds 2 points to an item carrying 18.

      ⛑ **AND THE DIRECTION IS THE FINDING.** Crafted gear was erratic; runes are **monotonically
      worse the higher you climb**, which is the clearest possible signature of the same root
      cause: gear totals are GENERATED and run 18 → 162 → 784 across the three bands (a 44x climb)
      while rune caps are hand-authored and run roughly 2-25 → 8-80 → 16-180 (about 7x). The ladder
      simply cannot keep pace, and every tier a player climbs makes their reward smaller.
      One outlier worth keeping: **Minor Rune of Vitality at 1.39x** is the only rune in the game
      that beats the item it sits on, because HP caps are authored an order of magnitude larger
      than stat caps. It is evidence the cap table was never sized against anything.

      **✅ STEP 8 — LADDER ONE IS FIXED, 2026-09-18.** Owner set the target for the PAIR: *"Beats a
      typical drop, loses to a lucky one"* — so crafted + runes lands near **1.15x** the median
      drop, split as `CRAFTED_BASE_SHARE = 0.80` for the canvas and the rest from runes.

      `DropTables.expected_item_power(level)` is the new single source: it **SAMPLES the real
      generator** and caches per level. Not a fitted formula, deliberately - affix VALUES are
      linear in level but item TOTALS are not (measured 2.25, 3.6 and 5.6 points per level at
      levels 8, 45 and 140, because higher levels roll better rarities and so more affixes), and a
      curve fitted by hand would become another hand-authored ladder drifting against a generated
      one. Asking the generator cannot drift, because it IS the generator.

      `CraftingDatabase.curve_sized_base_stats(recipe, drop_tables)` rescales a recipe's TOTAL to
      that curve while leaving its IDENTITY alone - a sword still gives attack, a helm defence.
      Shared rather than server-side on purpose: the probe calls the same function, so the
      instrument and the game cannot disagree about what a recipe produces.

      | | before | after |
      |---|---|---|
      | median vs drop | 0.49x | **0.80x** (exactly the target) |
      | per-SLOT spread | 0.12x – 1.04x | uniform ~0.88x |
      | per-LEVEL spread | 0.06x – 1.38x | 0.62x – 1.14x |

      **The per-slot fault is gone**, and the per-level spread that remains is residual variance
      between two independent 200-sample medians rather than a game fault.

      ⛑ **TWO INSTRUMENT CORRECTIONS ON THE WAY**, both caught before they became findings:
      * At 40 samples the curve was **non-monotonic** - 33 at level 5 against 19 at 15, 685 at 140
        against 603 at 150. Recipes sized against it would have gone BACKWARDS in places, reading
        as a content mistake and being near-impossible to trace to a sample size. 200 samples is
        monotonic and agrees with 800 to ~13%. `tools/probe/power_curve.gd` guards the property.
      * The worth probe originally sampled 60 drops against a curve built from 200, so it reported
        a per-level spread that was mostly its own variance. Matched to 200 - but still an
        INDEPENDENT sample, because checking the sizing against the number it was built from would
        be circular and would report 0.80x forever.

      **✅ STEP 9 — LADDERS TWO AND THREE, and the PAIR lands on target, 2026-09-18.**
      `CraftingDatabase.enchant_cap(stat, item, drop_tables)` replaces the flat per-item ceiling at
      **all nine enforcement sites** (one is left flat on purpose: it renders recipe DESCRIPTION
      text before any item is chosen, so there is nothing to scale against and inventing a level
      would print a number the player will not get).

      **Measured, the pair is now 1.15x a median drop at EVERY level** - 5 through 150, worst 1.15x,
      best 1.15x. The attack ceiling is **1 at item level 8 and 35 at level 140**, where it was a
      flat 60 at both: at level 8 that flat cap was more than triple the entire item.

      ⛑ **THE AUTHORED RATIOS SURVIVE; ONLY THE SIZE IS DERIVED.** attack 60 against strength 20
      says the author thought three points of attack were worth one of strength, and that judgement
      is preserved by scaling each entry against the table's own reference. Same principle as
      `curve_sized_base_stats`.

      ⛑ **AND THE REFERENCE HAD TO BE THE TOP THREE, NOT THE MEAN — caught by measuring.** The
      first version divided by the mean of all thirteen entries and put the pair at **1.68x**
      instead of 1.15x, *uniformly at every level* - which is the tell that the mechanism was sound
      and only the constant was wrong. The cause: a player enchants the three stats with the
      BIGGEST caps (max_hp 200, max_mana 150, attack 60), and those sit far above a mean dragged
      down by ten entries of 15-20. **Sizing a budget against the average while players spend it on
      the maximum overshoots by exactly that ratio.**

      ⛑ **`rune_worth.gd` IS NOW SUPERSEDED for the "is enchanting worth it" question** and says so
      at the top. The binding constraint is the item ceiling, not `rune_cap` - at level 140 the
      ceiling is ~35 while a Supreme rune's own cap is 16-180 - so a low ratio there no longer
      means enchanting is weak, and reading it that way would send someone to buff a constant that
      does not bind. `crafted_pair_worth.gd` is the instrument that answers the question now, and
      it measures the CEILING for exactly this reason.

      **⚑ FOR THE BALANCE BATCH:** this is a real player-power change - crafted gear went from
      0.49x a drop to a 1.15x pair - and the reference player has never carried crafted gear at
      all. It wants the chain.

      **☑ STEP 7 — AND THE REAL SHAPE, found while starting the fix.** `_roll_affixes` carries the
      line that reframes everything: *"Crafted items get 0 affixes - affixes come from Enchanter
      Runes."* So crafting and enchanting are **designed as a PAIR**: the blacksmith makes a canvas
      with base stats and no affixes, and the enchanter paints it with runes. A dropped item's
      affixes are what that pair is supposed to compete with.

      That is a good identity and it explains why both measured low - each was authored as if it
      were the whole answer, or neither was sized against anything. But it also means **the fix
      must size the PAIR**, not the two halves separately.

      **⛑ AND THERE ARE THREE FLAT LADDERS AGAINST ONE GENERATED CURVE, not two:**
      1. recipe `base_stats` - hand-authored constants (median **0.49x** a drop, erratic by level);
      2. `rune_cap` per recipe - hand-authored (**0.17x / 0.06x / 0.03x** by tier, worsening);
      3. **`ENCHANTMENT_STAT_CAPS` - a hard per-item ceiling that is FLAT ACROSS EVERY LEVEL.**
         attack 60, defense 60, max_hp 200, the stats 20 each, with `MAX_ENCHANTMENT_TYPES = 3`.
         Enforced at five sites in `server.gd`.

      **The third is the most damaging because it cannot scale at all.** At item level 8 a +60
      attack ceiling is more than triple the whole item (median total 18). At level 140 the same
      ceiling is under 8% of it (median 784). No rune rebalance can escape it - the cap binds
      first - so a fix that touched only rune values would measure better in a probe and change
      nothing in play above the mid game.

      **So the shared fix is one idea applied in three places:** derive all three from the same
      level curve the drop generator uses, and size the crafted-plus-runed PAIR against a dropped
      item rather than sizing either half alone.

      **So enchanting joins blacksmithing:** no cull, but its numbers must be derived from the same
      curve the drops use. That is now **three of five crafters** whose fix is one shared change -
      derive output from the drop curve - rather than content work.

      **✅ SCRIBING HAS AN IDENTITY, AGREED 2026-09-18: *the crafter who makes the world
      survivable*.** Every item reduces a RISK or a COST rather than adding power - which keeps
      Scribing out of the weapon/armour balance question, gives it ground no other crafter touches,
      and means it can never become mandatory, the failure mode of a crafter that makes power.
      Names state their effect, per the potion finding above.

      | item | what it does | status |
      |---|---|---|
      | **Safe Passage Scroll** | no encounters for N steps | ✅ **BUILT 2026-09-18** |
      | **Remains Ledger** | your corpse's exact location and contents | ✅ **BUILT 2026-09-18** |
      | **Waypoint Seal** | mark a spot, return to it once | ✅ **BUILT 2026-09-18** |
      | **Bestiary Page** | permanently reveal one species, account-wide | ✅ **EXTENDED 2026-09-18** |
      | ~~Scouting Report~~ | read a dungeon before entering | ❌ **cut - already covered twice** |
      | **Muster Sigil** | a party member joins you from anywhere | ⏸ deferred to the party arc |

      **⛑ THE SCOUTING REPORT WAS CUT BECAUSE IT WAS A THIRD OWNER OF A SOLVED JOB**, and the
      owner spotted it before I did: *"Are you suggesting we remove the ability to see whats in a
      dungeon when you step on its entrance space without these... I would want to ensure we aren't
      making a chore for players (like tools currently are)."* Checked rather than argued:
      the **entrance screen** already gives monster levels colour-coded against your own,
      modifiers, floors, ground, food and exit; and **Cartography rank + Locate** already handles
      finding a dungeon remotely, with its own progression and Valor cost. A scroll would have sold
      players something the game gives free, and charged them a slot and a craft for it.

      **✅ SAFE PASSAGE SCROLL — BUILT 2026-09-18.** Two recipes, a real ladder: 40 steps at skill
      12 and 120 at skill 34. **Sized against the measured road effect** rather than invented -
      roads already cut encounters from 67.2 per 200 steps to 6.7, so this is the portable version
      of a road for the ground between them, deliberately not longer or safer than one.
      ⛑ `safe_passage_steps` is a COUNTER, not a flag, which is the whole difference from
      `cloak_active`: cloak is a state you sit in, this is a budget spent by walking - which is
      what makes it a consumable worth carrying rather than a mode.
      ⛑ **A step is spent whether or not an encounter was due.** Decrementing only on a roll that
      WOULD have fired makes the scroll last wildly different lengths depending on terrain, and
      *"40 steps"* has to mean 40 steps or a player cannot plan with it.
      ⛑ **It ADDS rather than replaces**, so reading a second scroll early never throws away the
      remainder of the first - otherwise players learn to hoard them instead of using them.
      ⛑ It persists across logout, unlike cloak: it was paid for with materials.
      **Bonus:** its materials include `silverleaf`, which was one of the 16 EDIBLE-ONLY materials
      with no recipe use. The Scribe's items are a natural home for the orphans.
      Probe: `tools/probe/safe_passage.gd`.

      **Waypoint Seal pairs with post-to-post road travel** (also approved 2026-09-18): roads
      connect posts, the Seal connects the places that are not posts.

      **✅ THE OTHER THREE — BUILT 2026-09-18.**
      * **Remains Ledger** (skill 20) — exact coordinates, distance, direction AND contents of your
        last character's remains. ⛑ Worth more than it sounds: a corpse does **not** lie where you
        died. `_create_corpse_from_character` spawns it at a RANDOM spot at **half your distance
        from origin**, and the death notice gives only a compass direction and a distance rounded
        to ten tiles - so recovery is a genuine search, and this turns it into a walk.
        It needed new plumbing: corpses were keyed by `character_name` only, and under permadeath
        the player asking is a DIFFERENT character, so nothing linked anyone to their own remains.
        New corpses carry `account_id`; older ones fall back to the name rather than vanishing.
      * **Waypoint Seal** (skill 26) — first use marks, second use returns. ⛑ **Refused
        underground both ways**: marking inside a dungeon would store a world coordinate that is
        not where the player is, and returning out of one would bypass every exit rule a dungeon
        has, including the food and the walk back that are the run's real costs. Marking does not
        consume it, so a misplaced seal costs a walk rather than the item.
      * **Bestiary Page — EXTENDED, NOT BUILT, and that is the fifth shipped-but-unticked item.**
        A recipe with that exact id already existed, revealing a **random** unknown monster's HP to
        the **character** - which permadeath erases, so a page bought with materials was worth
        exactly one life. It now records **the foe in front of you** first (the moment knowing
        matters is while it is hitting you) and writes to the **account**, so it outlives the
        character that made it. The GDScript parser caught the duplicate id, which is luckier than
        it should have been - the audit trail said `bestiary 1 recipes` and I did not follow it up.

      **✅ AND THE ORPHANED MATERIALS: 9 → 6.** `silverleaf`, `black_pearl`, `ironwood` and
      `worldtree_branch` all now have a recipe that wants them.
      ⛑ **The potion cull created a NEW orphan and the audit caught it:** collapsing the five Banes
      removed Beast Bane, which was the only consumer of `wyvern_leather`. Folded into Banebrew,
      which reads correctly anyway - a brew that turns on anything should be made of a bit of
      everything. **A cull can orphan a material; re-run `crafting_materials_audit.gd` after one.**
      **✅ EVERY MATERIAL NOW HAS A DESTINATION — 2026-09-18. And four of the six "orphans" above
      were never orphans.**

      ⛑ **The audit was reading one of TWO recipe tables.** `crafting_materials_audit.gd` scanned
      `RECIPES` and not `GATHERING_TOOLS`, so it reported `ash_wood`, `oak_wood`, `darkwood` and
      `freshwater_pearl` as having no destination when each is used by **four** tool recipes. The
      three woods are the **weight-40 results of chopping**, so the false finding read as a serious
      loop failure — logging's main output going nowhere — and sat on this backlog as work to do.
      *An audit written around the wrong unit is as wrong as a guess and far more convincing.*

      The two real ones were `ice_crystal` and `rock_salt`, both **weight-35 mining** catches.
      Each now has a `refine_*` sink into **`magic_dust`** — value-neutral against the existing
      `refine_magic_dust` — which closes a loop, because `magic_dust` is what the **affix rework**
      consumes. Mine the surplus, refine it, rework a stat you don't want.

      ⛑ **NEW SINKS, NOT NEW INGREDIENTS.** Folding them into an existing low-tier recipe was the
      tempting fix and would have **gated** that recipe behind mining — a forager who never swings
      a pickaxe would have lost Minor Health Potions. A sink adds a route; an ingredient removes
      one.

      The audit is now a **guard** rather than a report: 0 orphans, and any new material with
      nowhere to go fails it. Edible-only (21 materials) is deliberately not a failure — food is a
      real destination. Proven by injecting a material with no recipe.

      **✅ THE BESTIARY READER — BUILT 2026-09-18.** Owner: *"add an inspect button or something in
      combat where if players have the bestiary for a certain monster they can view all the info on
      it while in or out of battle, and also compare that monster to others they know."*
      A **Know This Foe** button sits in the combat panel's top-right strip and opens the bestiary
      **focused on what you are fighting** - pinned to the top, highlighted, with the rest of your
      ledger beneath it in the same columns, which is the cheapest honest version of *compare*.
      ⛑ **The panel already existed and was reachable only from the menu, out of combat** - the
      wrong moment, because what a monster can DO matters while it is doing it. **Sixth time in
      this arc** the capability was built and the route was not: party invite, Duel for Valor, the
      fight log, the death log, the Bestiary Page itself, now this.
      ⛑ **The client has no monster data at all** - it carries `known_enemy_hp`, HP it has
      personally seen, and nothing else. So a comparison could not be assembled client-side however
      the UI were written, and a panel comparing KILL COUNTS would have answered a question nobody
      asked. HP / strength / defence / speed / abilities now travel with the summary, via a new
      `MonsterDatabase.base_stats_for_name()` (the bestiary only ever has a name).
      ⛑ **A Page overrides the upgrade tier**, which is the entire reason to craft one: it buys the
      full entry for ONE species - stats AND abilities - without buying the tier.
      ⛑ The button is deliberately **not** gated on owning a page: a player who knows nothing
      presses it and is told *"you have never killed a Wight - a Bestiary Page would write one for
      you"*, which is the moment they learn the item exists.
      Probe: `tools/probe/bestiary_reader.gd`.

      **✅ CUTS APPROVED:** the **18 combat scrolls** (one-shot spells competing with both cards and
      potions for the same moment, and the bulk of what makes Scribing unreadable) and Scribing's
      **8 material-making recipes**. Scribing goes from 44 recipes to roughly 6-10, each obviously
      worth making.

      **⚑ DECISIONS TAKEN 2026-09-18, and they are the plan for the consumable half:**
      * **✅ POTIONS — CUT AND RENAMED, DONE 2026-09-18. 35 recipes → 25, and 25 of 25 now name
        their effect** (was 16 of 35).
        ⛑ **The 19 "opaque" ones were mostly DUPLICATES, not just badly named** - reading what
        they actually did changed the job from a rename into a cull:
        * **6 flat/percentage heals** duplicating the existing Health Potion ladder. Cut 4; kept
          Restorative (50%) and Greater Restorative (70%) as the percentage ladder, which is a
          genuinely different thing from a flat heal at high HP.
        * **5 Bane potions** - dragon / undead / beast / demon / elemental - were **one mechanic
          wearing five names**, all +50% for 3 battles at skill 60-65, and the player had to guess
          which kind of trouble they were walking into *before meeting it*. Collapsed to one
          adaptive **Banebrew** at +30%, because it is never the wrong one. The five specific buff
          keys are still read in `calculate_damage`, so a potion already sitting in a live
          inventory keeps working.
        * **Potion of Resilience** (defense +10) was strictly dominated by Fortitude (+15, same
          stat, same duration, same skill). Cut.
        * **Prismatic Elixir** cost skill 55 for a SMALLER bonus than Elixir of Power at skill 40 -
          the ladder ran backwards. Cut.
        Survivors renamed to state their effect: **Defense Draught**, **Attack Elixir**,
        **Attack & Defense Elixir**, **All-Stat Elixir**, **Lesser / Greater Experience Elixir**,
        **Restorative / Greater Restorative Elixir**, **Banebrew**.
        ⛑ And the clarity probe's own word list had gone stale the moment the names changed - it
        flagged "Attack Elixir", "Restorative Elixir" and "All-Stat Elixir" as unclear because it
        had no entry for "attack", and "restore" does not match "restorative". A heuristic not
        updated alongside the content reports the CONTENT as broken. Fixed; one name (*"Battle
        Elixir"*) was genuinely vague and became "Attack & Defense Elixir".
      * **✅ QUALITY ON A CONSUMABLE IS YIELD, NOT POTENCY — DONE 2026-09-18.** Owner: *"you made
        an extremely potent healing potion, you dilute it into 2."* `QUALITY_YIELD`: Poor 1,
        Standard 1, **Fine 2, Masterwork 3**, Failed 0, and the craft message says why the extras
        are there so a Masterwork does not read as a bug.
        ⛑ **And the potency multiplier was REMOVED, not left alongside it.** Keeping both would
        compound - a Masterwork would give three potions each 50% stronger, i.e. **4.5x** a Standard
        craft rather than 3x. That is the kind of silent stacking that reads as *"crafting is
        overpowered"* months later with no obvious cause. Quality owns one lever.
        ⛑ **A knock-on worth as much as the mechanic: identical potions now STACK.** The crafted
        name carried the quality word ("Fine Health Potion"), so one recipe crafted five times made
        five near-duplicate piles. Owner, on inventory: *"Items and tools can buildup and takeover
        your backpack slots."* That is a real bloat win falling out of the change for free. The
        enhancement scroll KEEPS its prefix, because quality still scales a scroll's bonus.
        **Not done: the "promote to the next tier" half.** Yield covers the owner's example; tier
        promotion needs a recipe-to-recipe ladder mapping that does not exist yet.
        Probe: `tools/probe/consumable_quality_yield.gd`.
      * **✅ THE COMBAT ITEM LIST SAYS WHAT AN ITEM GIVES — DONE 2026-09-18.** Owner: *"the item
        info in combat needs improved so players can see what they do at a glance, Also shouldn't
        require them trying to do math, should just tell how much it will give them back."*
        Each row now reads `Greater Health Potion  x3   — +600 HP`, computed for THAT character.
        ⛑ **The number comes from `DropTables.consumable_heal_amount`, the same static the server
        calls in `handle_use_item`** - so what is shown is what is granted. Re-deriving the formula
        client-side would have been easy and wrong: a potion carries a FLAT part AND a percentage
        part together (tier 4 is `healing: 100` plus `heal_pct: 25`), which is exactly the sum a
        re-derivation drops half of. Measured: the same potion restores 150 HP to a 200 HP
        character and 600 to a 2000 HP one.
        A companion-targeted heal names its target, because `+340 HP` on a revive would be actively
        misleading mid-fight. Probe: `tools/probe/combat_item_gain.gd`.
        This is the same fault as the old stat descriptions: a number the player must compute is a
        number they do not have.

      **⚑ SPECIALISATION SHOULD BUY A SERVICE, NOT JUST A NUMBER — owner 2026-09-18.**
      *"We could possibly make it where if players choose to make a crafting profession their focus
      they get a quality of life improvement for themselves and other players. Examples would be
      like Blacksmith focused character able to repair their own gear or other players. We still
      need a place players can repair their equipment in posts so it's technically not gating
      content just providing convenience."*

      ⛑ **This is the strongest idea in the arc so far, and it is worth saying why.** Every other
      specialisation reward considered (bonus XP, cheaper materials, better quality) is a private
      number. A SERVICE is social: it gives a specialist a reason to be wanted by other players,
      which is the first crafting hook in the design that reaches outward. And it costs nothing in
      balance terms, because the post still does it - the specialist is convenience, not access.
      That distinction is the owner's and it is the whole safety argument: **a service a post also
      provides can never gate content.**
      Pairs with the **cheaper material cost** and **better quality** perks already chosen.

      **✅ SHIPPED 2026-09-18 — one field service per crafting focus.** Owner: *"we should try to
      have a similar type of specialisation service for each of the crafting focuses."*
      `Character.SPECIALIST_SERVICES` (5 entries) + `apply_specialist_service()`; one generic
      `handle_specialist_service` on the server, because the shape is identical for all five and
      five near-identical handlers is how one of them ends up with a rule nobody notices.

      | focus | service | mirrors | what the post has that this does not |
      |---|---|---|---|
      | blacksmith | Field Repair | post blacksmith `repair_all` | costs Valor, needs a post |
      | alchemist | Field Remedy | the post healer | costs Valor, needs a post |
      | enchanter | Recharge | resting | costs game time |
      | builder | Make Camp | Scroll of Safe Passage | 40 steps vs 25, one-shot, tradeable |
      | scribe | Chart a Course | Cartographer `Locate` | 15 Valor, needs a post |

      Free, portable, **180s cooldown**, and can act on a player standing **adjacent** — the part
      no post can do, and what makes it social rather than a menu. Probe:
      `tools/probe/specialist_services.gd` (4 of 5 proven by executing them against a character in
      a known-bad state; both halves proven to fire by injecting the fault).

      **⚑ OWNER 2026-09-18, on review: *"alchemist and enchanter service seem rather identical."***
      Correct, and the cause was worse than similarity. The post healer's SINGLE service (the block
      printing `"Recharge costs %d valor"`) cures poison, cures blindness, restores HP **and**
      refills all three pools. Field Remedy and Recharge were **one post service cut in half**, one
      half given to each trade — so neither mirrored anything whole, and the alchemist's half
      silently dropped blindness.
      **Done:** Field Remedy now mirrors the healer completely and belongs to the **alchemist**
      (healing is on-identity for a potion-maker). Probe extended to blind + drain the subject, so
      it can tell a complete mirror from the half that shipped; proven by re-injecting that half.
      **Open:** the enchanter now needs a service of its own — see the reroll loop below. Its
      Recharge is redundant until then.

      **✅ RESOLVED 2026-09-18 — and I was WRONG about two of the three.** "It overlaps with
      salvage" is not a measurement. Measuring each conversion separately:

      | recipe | verdict | what happened |
      |---|---|---|
      | **transmute** | **KEEP, untouched** | moves surplus **UP a tier** at a steady 75-83% return. Salvage cannot do this at all — and it is exactly the shape the owner wants for the surplus loop |
      | **extract** | **RATE FIXED** | a real cross-type conversion (leather/cloth → enchant mats), but a flat output against a doubling value ladder gave **33%-143%** depending on tier, on a material the recipe picks **for** you. Now priced off `MATERIALS`: **59-83%** everywhere |
      | **disenchant** | **REBUILT** | genuinely was strictly worse than salvage. Now returns **the runes that went into the item**, plus exactly what salvage would give |

      **The disenchant rebuild is the owner's own suggestion** — *"do you get runes back or
      something, if not isn't it just like salvage that we already have?"* `_remember_applied_rune`
      records each rune **at application**, because a finished item keeps only
      `affixes[stat] = value` and several runes can write the same stat, so working backwards from
      the number would be a guess. Gear enchanted before this update carries no record and is
      **told so** rather than left to wonder. It targets the **most-runed** item instead of your
      cheapest, and a full pack is reported rather than eating the runes silently.

      ⛑ **THE FOURTH VACUOUS CHECK OF THE SESSION, same shape as the other three.** The probe's
      extract-rate table computed the quantities **itself** from a hardcoded 0.80 and printed a
      convincing table — and passed clean while the server was reverted to the old flat 2, because
      nothing in it touched the server's arithmetic. Fixed structurally: the rate is now
      `CraftingDatabase.extract_output_quantity()`, the server calls it, and the probe calls the
      same function. Re-injecting the flat rate now fails at 33%.
      Probe: `tools/probe/specialist_recipes_earn_their_place.gd`.

      **⚑ THREE `specialist_only` RECIPES ARE DEAD WEIGHT — measured 2026-09-18, owner's challenge.**
      Owner asked whether transmute/essence and disenchant are worth anything. They are not:
      * **`_craft_disenchant`** (enchanter) — *returns no runes*. Destroys your **lowest-level**
        item (it picks, not you) for `max(1, int(3 * recovery_pct))` ore — **1 ore at Standard** —
        plus a chance of one enchant material. Ordinary salvage returns **~50% of the item's full
        crafting materials** including per-affix enchant mats, on an item you choose. Strictly
        worse than a free universal action.
      * **`_craft_render`** (alchemist, parts→essence) — `SALVAGE_ENCHANT_TIERS` already hands out
        magic_dust → arcane_crystal → soul_shard → void_essence → primordial_spark straight from
        salvage. `void_essence` is a 1–2 count ingredient in a handful of top-tier recipes.
      * **`_craft_transmute`** (alchemist, 5x T(N) → 2x T(N+1)) — same problem, competing with a
        free universal source.
      Cull or re-point them in the crafter identity pass. **And note `reforge_weapon`/`reforge_armor`
      are RECIPES, not the town blacksmith** — upgrading already lives in crafting, which is where
      the owner wants it. The town NPC's `pending_blacksmith_upgrades` is the separate thing still
      to remove.

      **⚑ NEXT — AFFIX REROLL LOOP (owner's idea, 2026-09-18).** *"making some type of loop that
      players can participate in to roll off a stat they don't like into something they do like
      (kind of like Diablo 3). It should be possible to do in town but easier to do through
      crafting focused individuals maybe?"*
      This is the **enchanter's identity** and it replaces Recharge. The town/specialist split is
      the same mirror structure as the other four services, and the town route is what satisfies
      the no-gating rule without needing a paired item:

      | | town | committed enchanter |
      |---|---|---|
      | where | a post station | anywhere |
      | cost | valor + materials | free, 180s cooldown |
      | target | yourself | yourself **or an adjacent ally** |

      Plumbing that already exists: `_craft_reforge` rerolls attack/defense ±10%;
      `_normalize_stat_key` + `SALVAGE_AFFIX_SKIP_KEYS` already enumerate an item's affixes
      cleanly; dropped items keep stats in `affixes`, crafted in `base_stats` (do NOT assume one).
      **Design question to settle first:** D3 rerolls one affix into a *different stat* (pick from
      2 offers, repeatable at rising cost) — that is the version that answers "roll off a stat I
      don't like". Rerolling the same stat's *value* is just `_craft_reforge` again.
      **✅ SERVER HALF SHIPPED 2026-09-18.** Reworks one affix into a **different stat** (the D3
      shape). `drop_tables.reroll_affix` / `rerollable_affixes` / `affix_reroll_cost`,
      `server.handle_affix_reroll` + `_quote`, enchanter service is now **Rework a Stat**.

      **⚑ THE BOUND — owner, same message:** *"we don't want these things to make it where players
      can infinitely upgrade for free... We don't want a player to just be able to keep buffing
      their same item for free infinitely."*
      A reroll is **structurally unlike the other four services**, and that is the thing to hold on
      to. Repair / heal / camp all **restore to a ceiling** — repeating them at the ceiling does
      nothing, so free-plus-cooldown is self-limiting. A reroll **compounds**, and a cooldown only
      makes compounding slow rather than bounded. So it carries five brakes, none of which is the
      cooldown:

      | # | brake | why |
      |---|---|---|
      | 1 | replaces, never adds | affix COUNT stays whatever rarity gave it; you cannot roll your way to more |
      | 2 | same pool only | a rare can never reach the epic-only `CHASE_SUFFIX_POOL` — rerolling must not be a back door to rarity |
      | 3 | fresh roll, no undo | **measured 37% come out worse.** D3 lets you keep the better of two, which converges on max — that *is* the "keep buffing" failure |
      | 4 | hard cap | `MAX_AFFIX_REROLLS = 5` per item, absolute |
      | 5 | rising, non-zero cost | town 1→2→4→7→11 mats + 20→120 valor; enchanter 1→1→2→4→6 mats, 0 valor. The specialisation is a **discount, never a waiver** |

      Paid in the **salvage enchant ladder** (`magic_dust` → `primordial_spark`), which gives those
      materials a destination — fault #1 of the crafting arc.

      ⛑ **The chase-pool check was VACUOUS on first writing and only fault injection found it.**
      The sample item was *uncommon* (2 affixes = prefix + suffix), so it has no **bonus** slot and
      the branch that could reach the chase pool never ran — deliberately routing the chase pool
      into that branch still produced a clean pass. The probe now uses an epic+ item and *prints
      how many rerolls actually hit a bonus slot* (294 of 600), so it cannot go quiet again.

      **✅ CLIENT SHIPPED 2026-09-18 too.** `Rework` button on the inventory bar → item picker →
      stat picker → result. **One panel serves both routes**, because the server already decides
      whether this player may rework from here (at a post, or a committed Enchanter anywhere) and
      says so plainly if not — a client-side copy of that rule would be a second place for it to
      drift. The enchanter's field button opens the same panel via `open_affix_rework`.
      The cap and the cost are shown **before** the player commits, every time; a cap discovered
      only at the refusal reads as the game breaking.
      Deferred: reworking an **ally's** item — the other four services act on an adjacent player,
      this one does not, so its "... for Ally" button is deliberately hidden rather than shown
      and broken.

      ⛑ **A second vacuous check, same session, caught the same way.** The probe asserted
      `count("rework_stat") >= 4` against an actual count of 7, so deleting an entire
      exclusion-list entry still passed. Each of the three lists is now named individually, and
      the re-injection fails. **A threshold well below the real value is not a check** — it is a
      number that happens to be true. That is now twice in one feature that fault injection found
      a probe asserting nothing.


      ⛑ **Two traps found while building it, both worth keeping:**
      * **Chart a Course nearly retired a Sanctuary upgrade.** The first version pointed at the
        nearest *unvisited post* — which is exactly the **Sanctuary Compass**, a permanent Valor
        upgrade whose tier 3 is "name + direction + distance". Handing that out free every three
        minutes is not mirroring a service, it is deleting one. It now mirrors the Cartographer's
        per-use `Locate` instead, and reads the **target's own** `cartography_locate_precision()`
        so the rank ladder cannot be skipped by standing next to a friend.
      * **✅ THE COMPASS POINTED THE WRONG WAY, AND HAD FOR A LONG TIME — found and fixed here.**
        Three functions in `server.gd` answered "which way is that" and **two had north and south
        backwards**. Ground truth is `world_system.gd:92` — `8: Vector2i(0, 1),  # north`, i.e.
        **+y is north** — confirmed independently by `get_direction_offset` and by the map
        renderer (`for dy in range(radius, -radius - 1, -1)`, so row 0 is the northernmost).

        | function | axis | blast radius |
        |---|---|---|
        | `_get_direction_text` | +y = north ✅ | 11 call sites, was correct |
        | `_compass_direction` | +y = south ❌ | 8 sites — **including the Cartographer's 15-Valor `Locate`**, which named north when the dungeon was south |
        | `_compass_direction_label` | +y = south ❌ | the **Sanctuary Compass** HUD glyph — a permanent Valor upgrade drawing ↑ for south |

        So two *paid* services have been sending players the wrong way on the N/S axis. East and
        west were always right, which is likely why it survived: the compass was correct half the
        time and wrong half the time, and "it pointed me wrong" reads as player error.

        **The comment is most of why nobody caught it.** `_compass_direction_label` carried
        *"same thresholds as `_get_direction_text` so the compass agrees with prose direction
        text"* directly above code returning the opposite letter for every north and south.
        Anyone verifying by reading agreed with it.

        Fixed structurally rather than per-site: one `WorldSystem.compass_octant(dx, dy)`, placed
        beside the direction table that defines the axis, and all three surfaces delegate to it.
        Probe `tools/probe/compass_axis_invariant.gd` checks the compass against
        `get_direction_offset` — the table the game actually **moves the player with** — rather
        than against a comment, and asserts no surface re-derives its own north. Proven to fire by
        re-injecting the exact shipped inversion (6 of 8 directions failed; E/W unaffected).


      **✅ THE TOWN BLACKSMITH REPAIRS; IT NO LONGER UPGRADES — SHIPPED 2026-09-18.** Owner: *"The
      Blacksmith in town should repair gear but no longer do any upgrading as that should be done
      through the crafting now."*

      ⛑ **This was not a cleanup — it was the game's ONE UNCAPPED POWER SOURCE, and it was live.**
      The backlog line said *"check what the NPC currently offers before cutting"*, and that check
      is what found it. `confirm_upgrade` did:

      ```gdscript
      equipped_item["affixes"][affix_key] = old_value + selected_affix.upgrade_amount
      ```

      with **no ceiling anywhere on the path**. `ENCHANTMENT_STAT_CAPS` exists but is only
      consulted by the ENCHANTING code (`server.gd:26563`); this wrote to `affixes` instead, so
      the cap never applied. The only brake was a quadratic cost.

      **Measured**, level-60 item, `attack_bonus` starting at 40:

      | upgrades | value | valor for that step |
      |---|---|---|
      | 1 | 55 | 1,750 |
      | 5 | 115 | 3,850 |
      | 10 | 190 | 6,475 |
      | 20 | **340** | 11,725 |

      A fresh level-60 drop rolls **45–69**. So one item could be pushed to ~5–7× what the
      generator produces, and **nothing stopped step twenty-one**. This is exactly what the owner
      ruled out while the reroll loop was being designed — *"we don't want a player to just be able
      to keep buffing their same item for free infinitely"* — except it was already shipped.

      Removed whole: the write, both cost helpers, the upgradeable-item scan, the select-affix
      message, and the client's Enhance button. **Signposted, not silently dropped** — the
      blacksmith screen says where enhancing went, and an old client asking to upgrade gets an
      answer rather than a dead button. The replacement is `Inventory → Rework`, which **trades**
      one stat for another instead of adding to it and is capped at 5 per item.

      **✅ AND A SECOND ONE, FOUND BY THE SAME SWEEP — `_craft_reforge`, 2026-09-18.** The Reforge
      recipe (*"reroll weapon/armor stats ±10%"*) read the value it was about to overwrite, so the
      roll **compounded** — a multiplicative random walk with no ceiling. It slipped past the first
      probe because it writes `item[stat]`, not `item["affixes"][key]`, and **multiplies** rather
      than adds.

      **Measured**, attack 100, median of 400 runs:

      | quality | 10× | 25× | 50× | 100× |
      |---|---|---|---|---|
      | STANDARD | 93 | 84 | 71 | **42** |
      | MASTERWORK | 122 | 160 | 254 | **769** |

      **Both ends were wrong, which is why nobody caught it.** At Masterwork the expected
      multiplier is 1.025 per reforge, so it grows exponentially. At Standard the expected
      multiplier is exactly 1.000 — but the **median** of a multiplicative walk sits below its
      mean, so "reroll ±10%" quietly destroyed more than half the stat. A trap at low quality and
      a money printer at high, from one line.

      Fixed by rolling against the stat's **original** value, pinned on first reforge. Reforging
      is now what it claims to be: a lateral reroll in a fixed band, repeatable without ratcheting
      either way. No cap needed — there is nothing left to compound.

      ⛑ **THREE PROBE CHECKS IN ONE SESSION ASSERTED NOTHING, and this one took two attempts.**
      v1 looked for the name `reforge_base` and an absent literal — an injection setting
      `base_val = old_val` defeated the fix entirely and passed clean. v2 looped 100 times while
      passing a **constant** base, so the loop was decoration. The fix was structural: the
      base-pinning moved **inside** `CraftingDatabase.reforge_stat`, so there is no argument a
      caller can get wrong, and the probe now reforges a **real item dictionary 100 times** and
      reads the item. It also prints the compounding case (median **538**) as a contrast, with its
      own assertion — if that stops compounding, the test is no longer measuring what it claims.
      **A source-text check cannot answer a question about behaviour over many applications.**

      **✅ AND A THIRD — the WISH equipment upgrade, 2026-09-18.** `_upgrade_single_item` did two
      things, and only one of them was right:

      | write | verdict |
      |---|---|
      | `item["level"] += 1` | **correct** — `_get_effective_item_level` damps it logarithmically above 50 |
      | `item["damage"] += 8%` | **read by nothing.** No aggregator consumes a top-level `damage` key, so the weapon branch — the headline of an *"Equipment Upgrade (x15)"* wish — did **nothing at all** |
      | `item["defense"]`/`["speed"]` += 8% | read **only** when `item.crafted`, and there it compounded with **no damping** |

      Measured, crafted armour at 50 defense, a wish granting a midpoint 9 upgrades, from a
      `wish_granter` monster at **10% per kill** so it repeats:

      | wishes | upgrades | defense |
      |---|---|---|
      | 1 | 9 | 95 |
      | 3 | 27 | 358 |
      | 5 | 45 | 1,410 |
      | 10 | 90 | **44,799** |

      Dead for most items and uncapped for the rest, from the same six lines. **Item power already
      has one owner** — `level`, through the damped curve. Two systems answering "how strong is
      this item", one damped and one not, was the whole fault; the raw writes are gone and the
      damped route is the only one.

      **⚑ AND THE OWNER PUSHED BACK, CORRECTLY — 2026-09-18.** *"So what does the wish do now?
      Ensure you aren't destroying our loot rewards. The wish isn't free, you have to kill a monster
      that can grant it. The balance should be in how often you can actually get a wish, not in
      making it useless."*

      Measured through the real aggregator (`tools/probe/wish_upgrade_worth.gd`, which equips the
      item and diffs what the player gets):

      * **Nothing was destroyed.** 4 of 6 item kinds are byte-identical before and after. **Dropped
        gear lost nothing at all**, confirming those writes were dead for it. Only crafted armour
        (−19%) and crafted boots (−7%) changed — the two that had been compounding undamped.
      * **But the reward was already broken at high level, and not by me.** A nine-upgrade wish was
        worth **+44% at item level 20 and +0% at level 300**, because `+1 raw level` barely moves
        `effective_level` once the log damping bites. A headline reward that quietly became nothing
        for exactly the players who fight the monsters that grant it.

      **Fixed by stating the grant in the unit that matters.** One upgrade now raises **effective**
      level by 3% (`Character.raw_level_for_effective` inverts the damping curve), capped at **+50%
      of the item's natural effective level**, recorded before any wish touched it:

      | item level | was worth | now worth (×9) |
      |---|---|---|
      | 5 | +175% | +58% |
      | 20 | +44% | +44% |
      | 50 | +98% | +60% |
      | 100 | +3% | **+30%** |
      | 300 | +0% | **+30%** |

      `WISH_EFFECTIVE_STEP` and `WISH_MAX_GAIN_FRACTION` are **tuning dials** — they set how big
      the reward is, and the owner should move them freely. The *safety* property is only that the
      cap exists, so a repeatable reward cannot run away. Pacing stays where the owner put it:
      how often a `wish_granter` shows up, not how little it gives.

      ⛑ **AND THE PROBE CAUGHT A WRONG NUMBER THAT HAD ALREADY SPREAD.** Printing
      `_get_effective_item_level`'s real output beside its docstring showed the docstring was
      **50 too low in every worked example** — it computed `15 * log2(51) = 85` and dropped the
      `50 +`. True values: **L100 = 135, L200 = 159, L500 = 182, L1000 = 198** (not 85/109/132/148).
      The wrong figure had already been copied into `drop_tables.gd` and quoted as a design target,
      and I repeated it in this arc's own comments before the probe printed it. Both copies fixed,
      and the probe now asserts the docstring matches the function.

      Probe: `tools/probe/no_uncapped_stat_growth.gd` — guards the **rule**, not the instance. It
      fails on any `affixes[key] = old + amount` write anywhere in the server, so the next one
      written by someone who never heard of the blacksmith is caught too. Proven by injecting that
      shape into an unrelated function.

      **⚑ TWO MORE DIRECTIONS, owner 2026-09-18:**
      * *"The UI for crafting will likely need redesigned as well once we are done. We want it to
        be organized in a way that makes it easy to understand what peoples options are."* — after
        the content, not before: the UI's job is to present a set of options, and that set is what
        this arc is changing.
      **⚑ AND THE OWNER CAUGHT THE HOLE THIS LEFT.** *"When you say the cost is that you can't have
      a second focus's recipes what does that mean exactly. Seems like that would gate recipes
      behind your commitment."* It did. **Measured: 109 of 254 recipes (43%) are `specialist_only`**
      — Scribing 64%, and spread across every skill band rather than confined to the endgame. A
      committed Blacksmith could never make 87 of them, permanently, with **no alternative route**:
      no post sells you a Void Blade. That sits badly beside *"rather than gate anything."*

      **✅ COMMISSION ROUTE SHIPPED 2026-09-18 (owner's choice of three).** A post NPC of the right
      trade will do the work for a fee. Identity stays strong; nothing is unreachable.

      ⛑ **THE LOAD-BEARING RULE — a commission lends a FOCUS, never a SKILL.** This came straight
      out of the owner's follow-up: *"what does continuing to level up a none commited job do if
      you can't build specialty items for it?"* If a commission lent the skill too, levelling an
      uncommitted trade would be pointless **and** commissioning would be a way to skip crafting
      progression outright. So you still meet the recipe's own skill requirement yourself — which
      makes levelling a trade you did not commit to directly worth doing, because it is the
      prerequisite for commissioning that trade's work. The probe asserts this **by ORDER**: the
      skill check must sit before the commission fork, and moving it after fails.

      **What levelling an uncommitted job actually buys — measured, since the owner asked:**
      * **Gathering** (every reader of `job_levels` in the codebase is one): hint accuracy
        (`level/100`), scratch-off slots and budget, chain caps, catch depth, and soldier's
        monster-part drop rate. All real, all commitment-independent.
      * **Crafting**: the number that matters is `crafting_skills`, not `job_levels` — two separate
        ladders, and a craft grants full XP to the skill and half to the job. On a difficulty-35
        recipe, skill 1 → 60 moves success **5% → 95%** and Masterwork share **0% → 66%**, plus the
        57% of that trade's recipes which are not gated, plus the right to commission the rest.

      A commission is pinned to **STANDARD** quality and can never reach Fine or Masterwork, so a
      real specialist stays worth finding — their ladder is the thing the NPC cannot match. The fee
      is `60 + 8 × skill_required` (100 Valor at skill 5, 780 at skill 90), so it tracks the content
      instead of going stale as recipes are added. You still supply every material.

      ⛑ **It reuses the entire craft pipeline behind one flag.** A parallel `commission_item`
      handler would have been a second copy of item production, XP, quality and party sharing —
      which is how two paths drift until they disagree in front of a player.

      **✅ AND THE PLAYER HALF, same day.** A commission is now a **buy order for work**:
      `item_type = "commission"` carrying a `recipe_id`, refused for anything a plain buy order
      could already cover. The **crafter supplies the materials** and is paid for them, which is how
      a commission works in the world and means nothing needs escrowing but Valor.

      ⛑ **IT REUSES THE BUY-ORDER SYSTEM RATHER THAN ADDING A SECOND ONE.** Orders already escrow
      Valor, survive a restart, pay an offline seller and deliver to an offline buyer — every hard
      part of a commission board, already built and exercised in production. (Found by checking
      before building, per the standing rule; `market_data` even had an unused `orders` key that
      turned out to be a live system.)

      ⛑ **Two failure modes that would have hurt a player, both caught in the build:**
      * **Name-matching.** A Masterwork craft is named *"Masterwork &lt;recipe&gt;"* while a Standard
        one is bare *"&lt;recipe&gt;"* — so matching an order by name would have rejected exactly the
        good ones, and accepted a same-named **drop** no crafter ever made. Crafted items now record
        `recipe_id` and fulfilment matches on that.
      * **Delivering a nameplate.** Every other order type is name-only, so the delivery path
        **rebuilds** the item from `{type, name, id}`. Doing that to a crafted weapon hands the
        buyer something with no stats, no quality, no affixes and no maker. Commissions now carry
        the real dict through both the online path and the offline queue, and the drain honours it.
      Proven by injecting the rebuild and watching it fail.

      **⚑ AND THE OWNER CAUGHT THAT IT HAD NO DOOR.** *"You mention commission it from an NPC and
      post it to a player but how do players actually do those things? Remember the answers should
      be UI based where possible."*

      ⛑ **The player half shipped with the server accepting a `recipe_id` and NOTHING able to send
      one** — `market_order_create` was reachable only through a market panel that had no recipe
      picker. That is the **"capability built, route missing"** defect for the **seventh time in
      this arc**, and I walked into it one commit after writing a probe section about it.

      **Both doors are at the BENCH, on the recipe**, because that is where a player meets the
      problem. Sending them to the market panel to hunt for a recipe picker would be a door in the
      wrong room.

      | you are looking at | you see |
      |---|---|
      | a recipe you cannot make | `Commission (540v)` — NPC, instant, Standard quality |
      | …the same recipe | `Post Job` — name your price, a player fills it at **their** quality |
      | a recipe you **can** make | `★ 2 player(s) want this — up to 1200 Valor` |

      That third row is the half that makes the loop close: **demand is shown where the crafter is
      already looking.** A separate commission board is a room nobody enters.

      ⛑ **A FIFTH VACUOUS CHECK, caught the same way.** The probe's "a Post Job button exists"
      searched for `"craft_post_job"` — which the HANDLER case also contains — so deleting the
      button entirely passed clean. **Two checks matching one string are one check.** B1 now names
      the button's `action_data` form, and removing the button fails.

      The crafter's name is stamped into `crafted_by` on hand-over. **Noted for the UI pass:**
      `crafted_by` is written in four places and **read by none** — crafters currently get no
      visible credit anywhere.
      Probe: `tools/probe/commission_lends_focus_not_skill.gd`.

      **✅ SHIPPED 2026-09-18 — and there were TWO gates, the quiet one worse than the famous one.**

      The level-5 trial cap is the one everybody talks about. But `can_gain_job_xp` also read
      `return gathering_job == job_name` once you had committed — so choosing mining froze
      **fishing, logging, foraging and soldier permanently**, and the same on the crafting side.
      **A player who committed had LESS access than one who never did**, which is the opposite of a
      reward and is not what the cap was ever advertised to do.

      Both are gone. Every job levels freely, forever. Committing now:

      | | before | after |
      |---|---|---|
      | your focus | the only job that could pass Lv5 | **+50% XP** (`COMMITTED_JOB_XP_BONUS`) |
      | every other job | **frozen for the life of the character** | levels normally |
      | specialist recipes | commitment | commitment (unchanged) |
      | field service | commitment | commitment (unchanged) |

      Commitment is still one-time and permanent — the cost is that you cannot have a *second*
      focus's recipes, not that the rest of the game stops paying you. Six player-facing surfaces
      updated (two hints, the commit confirmation, two "✗ LOCKED" renderings, the help page); the
      probe fails if any of the old copy survives.

      Probe: `tools/probe/jobs_are_a_carrot_not_a_fence.gd`, which **executes** a character rather
      than reading source — re-injecting the two gates fails it four ways.

      ⛑ **And its first run reported the bonus as 8.72x, which was the probe's own fault.** It
      levelled the committed subject to ~10 to make it eligible to commit and left the control at
      level 1, then compared `job_xp` — which is progress toward the *next* level and **resets on
      level-up**. Both subjects now level identically first and the test grant is too small to
      level either. *A baseline mismatch reads exactly like a wild balance bug.*

      * *"We may want to do away with locking people at level 5 of gathering/crafting jobs. Maybe
        let players specialize in a job to get additional xp in it and make leveling it give a
        benefit when doing it rather than gate anything."*
        **What that lock is today, measured:** `JOB_TRIAL_CAP = 5` in `character.gd`. A GATHERING
        job (mining / logging / foraging / soldier / fishing) stops earning XP at level 5 unless
        the player COMMITS, and committing binds them to that one job permanently
        (`can_gain_job_xp`). SPECIALTY jobs (blacksmith / builder / alchemist / scribe / enchanter)
        level freely; it is `specialist_only` recipes that gate on commitment instead.
        So the ask is: keep specialisation as a **carrot** (bonus XP in the chosen job) rather than
        a **fence**, and let job level buy capability rather than permission. Note that levelling
        already buys some capability - gathering scratch-offs are `2 + 1 per 25 skill, max 8` - so
        the benefit half exists and it is the gate half that is the complaint.

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

- [x] **SANCTUARY UPGRADES ARE PRICED OUT OF REACH — FIXED 2026-09-19.** Owner: *"most of the
      choices take too many baddie points... still not having enough for upgrades."* Measured on
      live, and worse than it reads: a **median real death earned 4 points** against a cheapest rung
      of 250 (62 deaths). Across **13 live sanctuaries, NINE had never earned a single point and
      NOT ONE had ever reached 5,000 lifetime.** The full ladder totalled **3,127,900** points -
      781,975 deaths to buy.
      **The shape was wrong too:** points came almost entirely from level milestones (50 at L10,
      150 at L25) while **40 of 50 real deaths happen at levels 1-9** and clear none of them. The
      counterweight to permadeath paid nothing to the players feeling permadeath most.
      **Two changes, both modelled on the 50 real deaths rather than chosen by feel:**
      * **Earn** - a flat `BADDIE_POINTS_PER_DEATH := 50` plus doubled XP/kill rates. A level-2
        death goes from ~0 to **50**; the median from 4 to **60**.
      * **Costs** - all 23 tracks repriced by RULE: a first rung is 4-10 deaths, each rung is 35%
        dearer than the last, and a track's premium is preserved but compressed (house_size costs
        ~2x the cheapest where it used to cost 20x). Ladder **3,127,900 -> 189,820**.
      ⚡ **Raising the earn alone was NOT enough, and I only found that by probing.** My first
      model costed six tracks; there are twenty-three. The owner picked "raise the earn, keep the
      costs" on that incomplete basis, and the probe failed 19 of 23 tracks straight after - which
      is what prompted the reprice. Probe: `the_sanctuary_is_reachable.gd`.
      **Still open, separately:** *"we need more interesting upgrades possibly branching ones."*
      This made the existing ladder reachable; it did not make it interesting. <!-- audited: 2026-09-19 --> Verified still open: `HOUSE_UPGRADES` in persistence_manager.gd still carries the original
      ladder untouched - house_size 5000/15000/50000, companion_slots up to 80000. Nothing has been
      repriced and no branching upgrades exist. Owner direction
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
