# Paths revamp (Wave 1) - DRAFT, 2026-10-21

Status: design draft from the owner's three rulings. Nothing built. Every number marked (G) is a guess.

## 1. The problem, measured from the code

- `shared/path_database.gd`: 3 archetype trees x 3 branches x 5 nodes, plus ONE class keystone per class.
  A character can ever take **16 nodes**. Every node is a flat one-time perk with no ranks.
- Points: `get_path_points_earned() = level/5 + milestones (6)`. All 16 nodes are affordable at **about L50**.
  At L10000 a character holds ~2,000 points and has nowhere to put them.
- No respec (`path_nodes` only appends), which only works because the tree is tiny.

## 2. Owner rulings (2026-10-21)

1. **Deep rather than huge**, but at least **3x today's options** (so 48+ nodes per character).
2. **More than passives**: some nodes should change how a card plays; "ideally something interesting for each class".
3. **Limited respec** (permadeath makes a free one wrong).

## 3. Proposed shape

### 3.1 Breadth: 16 -> ~50 nodes a character can see
- Each archetype tree grows from 3 to **6 branches** of 5 nodes (30 nodes). The three existing branches stay exactly as they are
  (same ids, so every saved character keeps what it took); three new ones are added per archetype.
- Each class gets a **Signature branch** of 7 nodes only that class can see (21 nodes in all, 7 per class).
  This replaces the single class keystone, which becomes the branch's capstone (`ck_*` ids kept).
- Per character: 30 + 7 = **37 nodes**, plus 3 **Ascendant** nodes (section 3.4) = **40**, 2.5x today; with the
  rank layer below, the number of *decisions* is far larger. If 3x on node count alone is wanted, the new branches grow to 6 nodes
  (36+7+3 = 46). **Open: node count or decision count?** I would count decisions, since depth was the ask.

### 3.2 Depth: ranks
- Plain nodes get **5 ranks**. Rank r costs r points (1,2,3,4,5 = 15 to max a node). Keystones and Signature capstones stay single-rank.
- Each rank adds a fifth of the node's full value, so the first point is cheap and the fifth is a commitment.
- Capacity is deliberately **larger than income**: ~37 nodes x 15 = ~555 points of capacity vs ~290 earned by L10000 (3.3), so about half the tree is reachable.
  Nobody finishes the tree; the question at every level is what to specialise in. That is the "deep" answer to maxing out at L50.

### 3.3 Point income to L10000 (G)
- Keep 1 point per 5 levels to L100 (20 points), so early play feels exactly as today (L50 = 10 + milestones).
- Then 1 point per 50 levels to L10000 (+198). Total ~218 from levels, plus ~70 from feats (3.6) = ~290.
- Band-gated tiers (3.4) are what make a level-3000 character differ from a level-300 one even with similar point totals.

### 3.4 Level-gated tiers: new KINDS of effect, not bigger numbers
Tier 5 of every branch stays the keystone. Three **Ascendant** nodes per class open at **L500 / L2000 / L6000** (G) and change
how a card plays. They are the same rank-1 shape as keystones, with a trade-off from the second one on (the card-upgrade rule:
"trade-offs only later").

### 3.5 Beyond passives: card-changing nodes (the Signature branch)
Each class's Signature branch is 7 nodes: 4 stat/threshold perks in the class's own engine (Momentum / Focus / Read / stance /
Berserk / Meditate ...) and 3 **card-rule** nodes. Candidate first draft, to be matched to each class's actual five-card deck
(I will pull the real decks with `-- cardnames` before writing a single node; these are placeholders showing the shape):

| class | idea for a card-rule node |
|---|---|
| Fighter | the opening stance also lasts through your first heavy hit, and you may re-brace once per fight at a cost |
| Barbarian | Berserk's defense penalty becomes a damage ramp that resets when you drop below 30% HP |
| Paladin | healing a companion also blesses you for a round |
| Wizard | the third spell in a row is free and cannot be countered |
| Sorcerer | a failed double-damage roll is banked and guarantees the next |
| Sage | Meditate also clears one debuff |
| Ninja | a finisher cast at full Read leaves 2 Read behind (the stale-gate lesson: tested with `cardtrace`) |
| Ranger | marked beasts take extra damage from your companion |
| Grifter | a pickpocket success feeds the class engine |

Rule from the owner's buff-transparency ruling: **every path effect that changes a fight is named in the opening line and the
mitigation/buff breakdown** ("Path - <node>"). Path talents were deliberately excluded from that rule before; with card-rule
nodes they must be included.

### 3.6 Milestones: feats from normal play (owner 2026-10-21)
Rulings: points should come from doing ordinary things, e.g. wearing a level-20 piece, killing 10 champions, beating 5 bosses.
Today only 6 one-time milestones exist, hooked ad hoc in `server.gd` (~6798, 38277). Replace the pattern with **one table of feats**
(`shared/path_feats.gd`): each feat = a counter key, a threshold ladder, and points per rung. A character carries `feat_counts: Dictionary`
(plus the existing `monsters_killed`, `dungeons_completed`), and one server funnel `_note_feat(peer, key, amount)` bumps the counter and
grants every rung it crosses (toast + 1 point). The six existing milestones become the first rungs, ids kept so nothing is re-granted.

Each ladder is geometric, so there is always a next rung from L1 to L10000 and the points stay a minor income beside the level curve (3.3).

| feat (counter) | rungs (G) | note |
|---|---|---|
| Slay monsters (`monsters_killed`) | 100, 1k, 10k, 100k, 1M | existing `hundred_kills` is rung 1 |
| Slay champions / Empowered (`empowered_kills`) | 1, 10, 100, 1k, 10k | rung 1 is `first_empowered_kill` |
| Slay 3-modifier Empowered (`triple_empowered_kills`) | 1, 10, 100, 1k | |
| Defeat bosses (`boss_kills`) | 1, 5, 25, 100, 500 | rung 1 is `first_boss_kill` |
| Clear dungeons (`dungeons_completed`, sum) | 1, 5, 25, 100, 500 | rung 1 is `first_dungeon_clear` |
| Clear a dungeon of each grade (distinct grades) | F..A, one rung per grade | rewards going places, not grinding |
| Wear a piece of level N (best equipped item level) | 20, 50, 100, 500, 2k, 8k | checked on equip, so gear progress pays |
| Wear a full set of one rarity (all slots >= rare, epic, legendary) | 3 rungs | |
| Slay in the Apex Frontier (`apex_kills`) | 1, 25, 250 | rung 1 is `first_apex_kill` |
| Complete quests (`completed_quests`) | 10, 50, 250, 1k | |
| Reach a level (the level itself) | 100, 500, 1k, 2.5k, 5k, 10k | the "band" rungs: pays at the moment each tier opens |
| Tame / hatch companions, fuse to a tier (`companion_feats`) | 1, 5, 25 | ties paths to the companion team |
| Gather and craft (`ore_gathered + wood_gathered + crafts`) | 100, 1k, 10k | rewards the non-combat loop |
| Spend gold at the Master Smith (purchases) | 1, 5, 20 | the new sink pays a point |
| Win a fight at <10% HP; win without taking damage | 1, 25 | skill feats, not volume |
| Survive a Phantom-hunt / defeat a Phantom (Wave 3) | reserved | added when Phantoms ship |

Totals (G): about 16 ladders x ~4-5 rungs = ~70 points, **about a quarter of the ~290 income at L10000**. Early rungs come in the first hours
(a feat every few levels, as the owner's examples), late rungs are the long-tail reason to keep doing the thing. Every rung announces itself
("Path point earned: Slay 10 champions") and the Path panel lists feats with progress, so the player sees WHY a point arrived (same
transparency rule as buffs).

Anti-grind: counters count real fights at or above the player's level band (no points for trivial monsters, as with Sanctuary points), and
dungeon/boss feats count once per instance, not per party member re-entering.

### 3.7 Limited respec (G)
- Refund **one branch at a time**, never the whole tree. Cost: **40 kills' gold at the current level per point refunded**
  (the economy's price unit, `GoldEconomy.kill_gold`), so respeccing a deep branch is a decision, not a click.
- At most **3 respecs per character**, ever; one extra at each of L1000 and L5000. Ascendant nodes can be respecced like others.
- Gold is run-bound and lost with the character, so this is also a gold sink.

## 4. Technical notes
- Data: `path_nodes: Array` of ids becomes `path_ranks: Dictionary {node_id: rank}`. Migration: each existing id -> rank 1 of that node
  (same ids, nothing lost). `get_path_effect_total` multiplies the node's per-rank effect by rank; the cache keys on a rank-sum.
- `get_path_points_available` = earned - sum of rank costs. Class keystone gate (`CLASS_KEYSTONE_SPEND_REQ`) is re-expressed as "points spent".
- Server: `handle_path_*` (around `server.gd:14546`) takes "buy a rank"; add `path_respec`; admin tool via /admin only.
- UI: the Path panel needs ranks, tier locks by level, and a respec button (action bar, no chat command).

## 5. Balance consequences (Wave 2)
- Path power is player-side: it enters the ONE chain with the other Wave 1 inputs. Per-class values only (global buffs wash out).
- Ranks are percent-based and small so L10000 power does not outrun the monster curve; the Wave 2 `make_char` model must hold a path build
  (a plausible spec per class, not a maximiser: "model the player, not the math").

## 6. Open questions
Resolved 2026-10-21: (1) 37 nodes, depth via ranks; (2) feats from normal play, section 3.6; (3) respec price/limits accepted;
(4) owner open either way. DECISION: ally-facing card-rule nodes reach human party members as well as companions (party play is a pillar;
the party probes cover it).
Still open: the exact feat ladders (3.6 table is a first pass) and the 21 Signature nodes, which come from the real decks.

## 7. Signature branches - first draft (2026-10-21)

Source of truth for names and engines: `-- cardnames` (run today) and `Character.class_passive_for`. Layout of every Signature branch (7 nodes):
**S1-S3 engine perks** (5 ranks each, small), **S4-S6 card rules** (single rank, each chained to the one before), **S7 the existing class
keystone** (`ck_*`, unchanged). Three **Ascendant** nodes per class (L500 / L2000 / L6000) sit outside the branch, listed last.
(G) throughout. Items marked `[verify]` depend on card behaviour I have not read line by line: each is read and traced with `-- cardtrace`
before it is written, so no node ships on a guess about its card.

The Oracle is stored as `Sage` (`ck_Sage`; node ids use `Sage`); the player sees "Oracle".

### Fighter - Momentum (Cleave, Shield Bash, Bulwark, Power Strike, Devastate)
| node | effect |
|---|---|
| S1 Drilled Stance | each rank: the opening stance is 4% stronger, up to 70% of the old full strength (it stays HALF strength by default; this is where the rest is earned, shown as "Path - Drilled Stance") |
| S2 Banked Momentum | start each fight with +1 Momentum per rank (max 5) |
| S3 Shield Wall | Shield Bash adds 4% of your defense as damage per rank |
| S4 Second Brace | Bulwark may be cast a second time in one fight, at double cost |
| S5 Staggering Bash | Shield Bash at 4+ Momentum also skips the enemy's next action [verify the stun rules] |
| S6 Aftershock | Devastate leaves 2 Momentum behind instead of spending all |
| S7 Drillmaster (existing) | all ability costs -15% |

### Barbarian - Rage (Power Strike, Cleave, Bull Rush, Berserk, Rampage)
| node | effect |
|---|---|
| S1 Thicker Skin | +1.5% damage reduction per rank while below 50% HP (offsets Blood Rage's missing-HP risk) |
| S2 Fury Reserve | +1 starting Rage per rank (max 5) |
| S3 Reaver | +3% lifesteal on Rampage per rank |
| S4 Berserk Discipline | Berserk lasts 1 round longer and its defense penalty is halved |
| S5 Bull Rush Breaks | Bull Rush removes one enemy buff [verify monster buff model] |
| S6 Unchained | Rampage cast at max Rage ignores monster mitigation this round |
| S7 Blood Rage (existing) | no Berserk penalty, +3% damage a round (max +30%) |

### Paladin - Conviction (Reproach, Invocation, Shield of Faith, Lay on Hands, Judgement)
| node | effect |
|---|---|
| S1 Steadfast | +1 Conviction per rank when a blow lands on you while below 50% HP |
| S2 Sanctified | +4% bonus vs undead/demons per rank |
| S3 Mercy | Lay on Hands heals +5% per rank |
| S4 Shared Blessing | Lay on Hands also heals your companion and any party member for half |
| S5 Radiant Shield | Shield of Faith reflects 20% of blocked damage as holy damage |
| S6 Verdict | Judgement at max Conviction executes below 15% enemy HP [verify cap and lethal rules] |
| S7 Crusader's Aura (existing) | 2% max HP on kill, +40% vs undead/demons |

### Wizard - Focus (Magic Bolt, Blast, Forcefield, Arcane Surge, Meteor)
| node | effect |
|---|---|
| S1 Deep Focus | +1 starting Focus per rank (max 4; Focus caps at 5) |
| S2 Precision | +2% spell crit per rank |
| S3 Resonance | Meteor does +5% damage per rank per Focus held |
| S4 Flowing Casting | the third spell cast in a row is free |
| S5 Warded Surge | Arcane Surge also grants a small Forcefield [verify the card] |
| S6 Twin Bolt | Magic Bolt at 5 Focus casts twice (same shape as the existing double-cast keystone) |
| S7 Archmage (existing) | 15% of spells cast twice |

### Sorcerer - Volatility (Chaos Bolt, Wild Surge, Frost Nova, Forcefield, Cataclysm)
| node | effect |
|---|---|
| S1 Loaded Dice | +1% double-damage chance per rank |
| S2 Steady Hands | -1% backfire chance per rank (min 0%) |
| S3 Fractured Frost | Frost Nova damage +5% per rank |
| S4 Banked Chaos | a failed double-damage roll is banked: the next spell is guaranteed to double |
| S5 Controlled Backfire | a backfire also hits the enemy for half |
| S6 Cataclysm Reborn | Cataclysm cast on a banked double also resets Volatility [verify] |
| S7 Chaos Theory (existing) | double-damage chance 25% -> 35% |

### Oracle (stored Sage) - Insight (Mind Lance, Stillness, Transfix, Premonition, Unmaking)
| node | effect |
|---|---|
| S1 Clear Sight | +1 Insight per rank on an unharmed round, on top of Foresight (max +3) |
| S2 Quiet Mind | Premonition absorbs +6% more per rank |
| S3 Piercing Lance | Mind Lance +4% damage per rank per Insight held |
| S4 Gentle Stillness | Stillness also clears one debuff from you |
| S5 Deep Transfix | Transfix lasts 1 round longer |
| S6 Final Reading | Unmaking at max Insight cannot be resisted and refunds 3 Insight |
| S7 Transcendence (existing) | Meditate also restores 5% max HP |

### Grifter - Leverage (Size Them Up, Distract, Sabotage, Sucker Punch, Double Cross)
| node | effect |
|---|---|
| S1 Loaded Odds | +1 starting Read per rank (max 4) |
| S2 Quick Fingers | +3% pickpocket success per rank |
| S3 Cash Out | Double Cross deals +2% damage per rank per Read spent |
| S4 Hot Hand | a successful pickpocket feeds +1 Read |
| S5 Double Dealing | Sabotage may be cast twice in a row |
| S6 House Edge | Double Cross returns half the Read it spent on a kill |
| S7 Cutpurse King (existing) | pickpocket always succeeds, +50% materials |

### Ranger - Aim (Track, Snare, Weak Point, Ambush, Killing Shot)
| node | effect |
|---|---|
| S1 Steady Aim | +1 starting Aim per rank (max 4) |
| S2 Hunter's Reach | +3% damage vs beasts per rank |
| S3 Bowyer | Killing Shot +4% damage per rank per Aim held |
| S4 Pack Hunter | marked monsters take +15% from your companion |
| S5 Pinning Snare | Snare also lowers enemy dodge |
| S6 Deadeye | Killing Shot at 8 Aim cannot be dodged (the Ranger never crits, so its payoff is reliability) |
| S7 Apex Hunter (existing) | beast bonus +40%, +10% XP |

### Ninja - Read (Mark, Hamstring, Ambush, Phantom Strike, Assassinate)
| node | effect |
|---|---|
| S1 Patient Blade | +1 starting Read per rank (max 4) |
| S2 Ghost | +2% flee and dodge per rank |
| S3 Edge | Assassinate +3% lethal chance per rank |
| S4 Lingering Mark | Mark lasts 2 more rounds |
| S5 Shadow Echo | an Assassinate that does not kill leaves 2 Read behind (traced with `cardtrace`, since the Ninja's finisher gate went stale once) |
| S6 Vanishing Act | Hamstring has a 25% chance to vanish you for a round |
| S7 Shadow Lord (existing) | Vanish costs 50% less, +15% flee |

### Ascendant nodes (one set per class; L500 / L2000 / L6000)
Each rewrites one card. The L2000 and L6000 ones carry a trade-off (the card-upgrade rule). Drafts only:

| class | L500 | L2000 | L6000 |
|---|---|---|---|
| Fighter | Bulwark also taunts: the enemy must target you | Power Strike spends all Momentum for +25% each | Opening stance returns to full strength but you cannot flee |
| Barbarian | Rampage heals for 10% of damage dealt | Berserk is permanent, defense -20% | A death save at 1 HP, once per fight |
| Paladin | Judgement heals the lowest-HP ally | Invocation lasts the whole fight at half strength | Judgement costs 3 less Conviction but consumes all |
| Wizard | Meteor leaves a burn | Forcefield is cast free once per fight | Focus cap rises to 7, spells cost 25% more |
| Sorcerer | Cataclysm cannot backfire | Backfire chance 0%, but double chance 20% | Chaos Bolt chains to a second hit |
| Oracle | Premonition triggers twice | Transfix applies to a second enemy in groups | Unmaking costs 2 less Insight but cannot kill bosses |
| Grifter | Double Cross refunds a card | Sucker Punch always crits on a Distracted foe | Leverage doubles, but you start fights at -25% HP |
| Ranger | Track reveals and lowers enemy defense | Snare slows the monster's next two attacks | Killing Shot +100% but requires 8 Aim |
| Ninja | Phantom Strike carries over to the next fight | Hamstring and Mark apply to a second target | Assassinate costs all Read, +50% lethal |

All of these are drafts for the owner to react to. The keystones and passives named are the current game's; the rest are new.

## 8. Using paths to close the class gaps - and the instruments that needs (2026-10-21)

Owner ruling: paths are the per-class lever that shores up each class's gaps and brings the classes to similar power. They are
player-side and per-class, which is exactly the kind of change that survives a monster refit (a global buff washes out; this does not).
Any simulation or metric needed for that gets built.

### 8.1 Where the gaps are today (measured: `classrisk`, stance 0.5, Ninja policy fixed, 150 fights/cell, 2026-10-20)
Average gear, win% / death%: at L100 Wizard 87/4, Sorcerer 81/5, Ranger 79/3, Grifter 81/7, Fighter 82/6 against **Ninja 65/7, Paladin 70/7,
Sage 71/11**; at L500 Wizard 91/3 against **Paladin 63/9, Fighter 69/8, Sage 71/9**. Undergeared the spread is wider (Fighter 65%, Paladin 55%
at L100 against Wizard 83%). Beyond L500 there is no measurement at all, and characters go to L10000.

### 8.2 Target, not siblings
"Similar power" means **each class hits the same absolute band at each level** (what BALANCED means: most die by design, death risk
falls with progression). It does NOT mean "match the strongest class". Tuning to siblings is a treadmill (`feedback_tune_to_targets`):
Wizard is both the highest and possibly over the band. So the paths budget can also pull an over-performer DOWN (its engine perks get
smaller ranks, or a trade-off on its Ascendants), and the per-class path budget is sized from the gap to the target band, not to a rival.

### 8.3 Instruments to build (in this order; each is its own probe/audit with a PASS line)
1. **Path support in the instrument.** `make_char` takes a path SPEC: a per-class ordered priority list, spent from the points the
   level has earned (`PathPoints.earned(level, feats)`). Specs model the PLAYER, not the maximiser: a "typical" build per class plus two
   alternates per class (defensive / offensive), never a solver-picked optimum. Without this nothing below can run.
   Proof it works: identical numbers after a real change mean the change is not running, so each node gets a "fires" assertion.
2. **`pathfires` (node coverage).** For every node, cast the card/hook with and without it and require a measurable difference in the
   state it claims to change (the `upgradefit` pattern: it found four upgrades that did nothing). Catches dead nodes before any balance
   run, and catches the Ninja-style stale-gate defect for path nodes.
3. **`pathvalue` (marginal worth).** For each node, rank 1 and rank 5, per class, at L30/L100/L500/L2000: paired A/B on the same seeds
   (per-cell seeding, then re-measure something unchanged: it must come back byte-identical). Output: win pp, death pp, damage/turn, with
   a confidence flag (±10pp rule: nothing under ~6pp is called a difference). Tells us which nodes are worth their points.
4. **`pathcurve` (point economy).** Points earned by level and by feat versus tree capacity, per class; reachable fraction at each level;
   confirms the tree is never full before L10000 and never empty of choices before L50.
5. **`pathspread` (no dominant build).** Per class: best spec vs median spec vs worst reasonable spec. Deep means choices matter but none
   is mandatory; flag any class where one spec beats the median by more than ~10pp or where the "typical" spec is a trap.
6. **`pathgap` (the closer).** Per class and level band: gap to the target band with the typical spec, then the smallest path budget (points
   by branch) that closes it, reported as a per-class path profile. This is the number that feeds the nodes' rank values. It reports
   whether the class is bound by its clamp (saturation is not convergence).
7. **High-level reach.** `classrisk` stops at L500. Extend the cells to L1000/2500/5000/10000 using the existing reference curve and
   check the curve's top end against live saves before trusting it (the reference player was wrong once without anyone seeing it).
8. **Feats telemetry.** The valor-ledger pattern: `feat_ledger.json` counts rungs earned per feat per hour of play, so the ladder numbers
   (3.6) are retuned from real play rather than guessed. (There is none yet; this is the same blind spot as the economy numbers.)

### 8.4 Process, so the chain is run once
Build data model and wiring -> `pathfires` -> `pathvalue`/`pathcurve`/`pathspread` (iterate here, 2-4 minutes each) -> per-class `pathgap`
profile -> set the rank values -> THEN the single Wave 2 chain (`preflight` -> `speciescal` -> `refcal` -> `rolecal`) with paths in the
model. Paths are never tuned by running the chain repeatedly.

### 8.5 Design constraint carried over: LESS CONDITIONAL (BACKLOG, owner 2026-09-18)
Owner direction: *"Path's need revamped and should be class specific and less conditional"*: a node that only fires in a narrow
circumstance reads as dead weight at the point of choosing. Several of my section 7 drafts are conditional (`at 4+ Momentum`, `at max
Rage`, `below 50% HP`). Rule for writing the real nodes: **a rank-able engine perk must always do something every fight**; a threshold
is allowed only on card-rule nodes where the threshold IS the class's engine (Momentum, Read...), and the card text must say it plainly.
`pathfires` reports how often each node's condition is actually met in a fight; a node met in under ~25% of fights is rewritten.

## 9. Build status (2026-10-21)

**Slice 1 - data model: BUILT** (`shared/path_points.gd`, `shared/path_feats.gd`, `PathDatabase.max_rank/rank_effect`, Character ranks/feats/respec
fields, server `handle_path_spend` (rank-aware), `handle_path_respec`, `_check_feats`, the ranked Paths panel). Probe: `path_ranks_and_feats`.

Decisions made while building (one value per rank = what the node was worth before ranks, so no saved character lost anything):
- A rank adds the node's listed value AGAIN (so a +5% node is +25% at rank 5), not a fifth of it. Differs from 3.2's wording; it is the choice that
  does not nerf anyone, and `pathvalue` will say whether 5 ranks of that is too much.
- Only small plain percent perks (listed amount <= 10, no duration/boolean keys) get 5 ranks; the rest are single-rank until `pathvalue` measures
  them. New nodes name their own `ranks`.
- Saves from before ranks: each node id becomes rank 1; each legacy milestone is marked as rung 1 of its feat, so earned points do not change.
- Feats wired so far: kills, champions, 3-modifier champions, bosses, dungeons, Apex, quests, best gear level, level, Master Smith purchases.
  Not yet: distinct dungeon grades, full sets, companions, gather/craft, skill feats (need counters and hook sites).
- Party kills do not yet bump feat counters (the party fight path has no solo-style kill block); fixed with the Sanctuary-points party gap.

Next: the six new branches per archetype and the Signature branches (content), then the instruments in section 8.

**Slice 2 - Fighter Signature branch: BUILT (2026-10-21).** `PathDatabase.SIGNATURES`, `signature_nodes`, chain S1..S6 + `ck_Fighter`; panel row with its own respec;
`Character.path_summary()` puts a "Path: ..." line in every fight's opening message. Probes: `path_nodes_are_wired` (every effect key has a reader - it found
that the Mage's Combustion never worked; fixed), `fighter_signature_fires` (each node changes the fight it names, with and without).
Design changes forced by reading the cards (the `[verify]` rule working):
- S4 "Second Brace" -> **Lasting Guard** (Bulwark +2 rounds): Bulwark has no once-per-fight limit, so "cast twice" meant nothing.
- S5 "Staggering Bash" -> a stunning Shield Bash builds an extra Momentum (Shield Bash already stuns; its stun decays per use and is hard-capped at 2 in a row).
- S1 Drilled Stance is capped at 5 ranks = +20% (ratio 0.5 -> 0.7), recorded on the fight and named in its opening line.
- S2 Banked Momentum caps at 3 ranks (Momentum max is 5).
Next: the other eight Signature branches, one class at a time, each read against its cards; then the six new archetype branches.

**Slice 3 - Barbarian and Paladin Signature branches: BUILT (2026-10-21).** Probe `barbarian_paladin_signature_fires` (22 checks, each node with and without).
Changes from the section 7 drafts, all forced by reading the cards:
- Barbarian: S5 "Bull Rush Breaks" is now -10% monster attack for 3 rounds (the weakness debuff a companion applies; the game has no monster-buff
  list to strip). S6 "Unchained" is now a stun at full Rage (it was "ignore mitigation", which has no single place to hook). Fury Reserve caps at 2 ranks
  because every Rage is +16% damage. Thicker Skin is named in the mitigation breakdown as "Path - Thicker Skin".
- Paladin: S1 is "Resolute" (first blow each fight builds extra Conviction) instead of a below-50%-HP trigger, to obey the less-conditional rule;
  S2 is Bastion of Faith (+2% max HP per rank) instead of undead bonus, which is a narrow condition. S4 is **Cleansing Hands** (Lay on Hands cleanses
  poison/bleed): "heals your companion and party" cannot be built as written - companions have no HP bar in combat, and the party fight has its own
  card path. Ally healing for a human teammate is filed for the party-combat pass, not dropped. S5 is Radiant Shield (+10% damage reduction with Shield of Faith,
  sourced as "Path - Radiant Shield"). S6 is Verdict (+10 points of Judgement's lethal chance; the card face quotes it).
Card faces stay truthful: Mercy and Verdict change the quoted heal and lethal numbers, covered by the probe.

**Slice 4 - Wizard, Sorcerer and Oracle Signature branches: BUILT (2026-10-21).** Probe `mage_signature_fires` (27 checks; random rolls compared on the same seed,
card quotes compared on ONE character with the node toggled - two `make_char` calls are two different characters, which is what made the first run fail
six checks that were not the nodes' fault).
Found while reading the cards:
- **The Sorcerer's class keystone Chaos Theory (35% double) was read only by the basic attack.** A deck-driven Sorcerer almost never uses the basic attack, so
  the keystone did nothing for the cards. `_chaos_adjusted` now folds it (and Loaded Dice / Steady Hands) into the passive every spell reads. This is a real
  power change for any Sorcerer that took the keystone; it goes into the Wave 2 model.
- Drafts that did not survive the card: Sorcerer "backfire also hits the enemy" (a backfire already halves the spell and still hits), Wizard "third spell
  free" (no single mana hook), Wizard "Warded Surge" (replaced by Smoldering Impact: Meteor leaves a burn), Oracle "Stillness clears a debuff" (now builds
  an extra Insight, the engine), Oracle "Final Reading refunds Insight" (now +8 lethal chance).
- An Oracle earns Foresight Insight even with the monster turn suppressed, so Gentle Stillness is tested as "one more than without".
Nodes: Wizard Deep Focus, Resonance (Meteor +3%/Focus), Echoing Casts (+2% double-cast), Surging Focus, Twin Bolt, Smoldering Impact. Sorcerer Loaded Dice,
Steady Hands, Fractured Frost, Banked Chaos, Controlled Backfire, Cataclysm Unbound. Oracle Clear Sight, Quiet Mind, Piercing Lance, Gentle Stillness, Deep Transfix,
Final Reading. Card faces quote Resonance, Fractured Frost, Cataclysm Unbound, Piercing Lance and Final Reading.
Remaining Signature branches: Grifter, Ranger, Ninja.

**Slice 5 - Grifter, Ranger and Ninja Signature branches: BUILT (2026-10-21). All nine classes now have a Signature branch.** Probe `trickster_signature_fires`
(24 checks). Card faces quote Dirty Tricks, Cash Out, Hunter's Reach, Bowyer, Deadeye and Assassin's Edge through the same functions the casts use
(`_finisher_path_mult`, `assassinate_chance`).
Changes from the section 7 drafts, all forced by the cards:
- Grifter: S2 is **Dirty Tricks** (Sucker Punch +4%/rank) because Pickpocket is not in the Grifter's deck; S4 **Hot Hand** is Distract building an extra Read;
  S5 **Deep Cuts** raises Sabotage's 50% cap to 65%; S6 **House Edge** is Double Cross leaving 2 Read. ("Sabotage twice in a row" had no rule to break.)
- Ranger: S2 **Hunter's Reach** is Weak Point +4%/rank (a beast bonus is a narrow condition); S4 **Eagle Eye** (Track's bonus +10 points); S5 **Pinning Snare**
  (-20% accuracy; the game has no enemy dodge); S6 **Deadeye** is +25% at full Aim (Killing Shot already cannot be dodged). Steady Aim caps at 2 ranks: each Aim is +11% damage.
- Ninja: S2 **Keen Edge** is +4% CARD crit DAMAGE per rank, not crit chance - **a level-60 Ninja on average gear is already at the 75% crit cap**, so chance would do
  nothing. S4 **Marked for Death** (Mark builds an extra Read); S5 **Shadow Echo**; S6 **Vanishing Act** (Phantom Strike grants +25% evasion for 2 rounds, sourced to the Path).
Found while reading (filed, not fixed - each is the owner's call because it changes player power):
- **The Assassinate keystone (`crit_damage_pct` +50%, and its -10% `noncrit_damage_pct`) is read by the basic attack alone**, like Chaos Theory was: a deck-driven
  trickster never gets it. Fixing the upside without the downside would be pure gain, so both must move together.
- **Companion/monster "slow" (`monster_slowed`) is written and never read** (only displayed): the slowing cards do nothing to the fight.
- Track's log line said "+10% damage bonus" whatever the real figure was (it is 8% on an unranked card); it now prints the real number.

**Slice 6 - the six new archetype branches: BUILT (2026-10-22).** 45 nodes (3 archetypes x 3 branches x 5), appended after the original three so every saved
character keeps its ids. Probe `archetype_branches_fire` (the unit is the EFFECT KEY, 31 keys incl. reused ones; a closing check fails if any key used by the 45
nodes was not exercised). Each plain node has 5 ranks, each branch ends in a keystone with a price.

| archetype | branch | nodes (rank 5 unless noted) |
|---|---|---|
| warrior | Vanguard | Steel Nerves (-10% damage taken) / Shrug It Off (+5% max HP a round below half) / Stand Firm (hits over 25% max HP cut 30%) / Rally (kill: -20% damage 3 rounds) / **Immovable** (-15% damage taken, cards -10%) |
| warrior | Slayer | Opening Salvo (first card +40%) / Executioner (+30% under 30% HP) / Sundering (+5% per hit, 5 stacks) / Bloodletter (kill: +15% stamina) / **Glass Cannon** (+25% damage, -15% max HP) |
| warrior | Provisioner | Field Medic (+40% potion healing) / Second Helping (potion: +20% stamina) / Iron Stomach (poison, bleed -40%) / Antidote Lore (potion cleanses) / **Last Rations** (potion: -25% damage 3 rounds, -10% max HP) |
| mage | Arcana | Varied Arsenal (+10% per distinct card cast, up to 3) / Echo (15% refund) / Opening Gambit (first card -50% cost) / Siphon (+5% mana a card) / **Overdrive** (every 4th card free, +30%; -10% max mana) |
| mage | Warding | Mana Ward (-10% damage taken) / Blur (-10% hit chance, relative) / Reflective Veil (20% reflected) / Steady Breath (+2.5% HP a round) / **Pale Veil** (first 2 rounds -50% damage; spells -8%) |
| mage | Lorekeeper | Focused Study (kill: +15% mana) / Arcane Alchemy (potion: +20% mana) / Quickened (10% extra turn) / Mind Over Matter (hit taken: +5% mana) / **Prodigy** (10% extra turn; cards cost 15% more) |
| trickster | Gambit | Lucky Streak / Pilfer / Slippery Hands / Sleight of Hand (shared keys with Arcana) / **High Roller** (8% extra turn; take 10% more damage) |
| trickster | Evasion | Light Step (-10% hit chance) / Slip Away (big hits -30%) / Feint (first 2 rounds -30%) / Counterfeint (hit taken: +5% energy) / **Untouchable** (-12% hit chance; -15% max HP) |
| trickster | Cutthroat | Hit Where It Hurts / Open Wounds (Sundering) / Predator's Eye (+5% crit) / Vicious Rhythm (Opening Salvo) / **Cold Blood** (card crits +25 points; -10% max HP) |

Design points that came out of testing, not out of the draft:
- **Dodge is relative and applied AFTER the 40% floor.** A level-60 Ranger already sits on the floor, so a flat "-12 to hit" before the clamp did nothing for exactly the
  builds that take the Evasion branch. "N% less likely to hit you" now multiplies the clamped chance (floor 25%).
- **Rally and Last Rations use their own buff type, `path_guard`.** Buffs of one type merge to their maximum, and the Fighter's stance defence (39%) swallowed a 20%
  Rally entirely. `path_guard` multiplies with every other defence, appears in the mitigation breakdown named for the Path, and has icon, hover and help text.
- **Counters are written after a cast and read before it** (`path_cards_cast`, `path_cards_seen`, `path_sunder`), so a card face quotes exactly what the cast will do
  and a quote never advances anything. Overdrive's free cast and Opening Gambit's discount live in the cost funnel (`apply_variable_cost`).
- **Variety is the only node family that directly rewards playing the whole deck** (Varied Arsenal / Lucky Streak); it is the first piece of the combat-variety work
  (`docs/design/combat_loop_variety.md`) that landed.
- The panel shows six branches as two rows of three inside a scroll area.
- **Not covered:** party (co-op) fights use their own damage path, so the card-damage nodes (Opening Salvo, Executioner, Sundering, Varied Arsenal, Overdrive) and
  the cast riders do not yet apply there; the mitigation, dodge, sustain and kill nodes do where the shared funnels are used. Filed as a known gap, same as feats.
