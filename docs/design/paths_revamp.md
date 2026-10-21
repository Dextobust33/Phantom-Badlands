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
