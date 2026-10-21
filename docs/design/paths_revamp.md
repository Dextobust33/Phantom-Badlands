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
- Capacity is deliberately **larger than income**: ~37 nodes x 15 = ~555 points of capacity vs ~220 earned by L10000 (3.3).
  Nobody finishes the tree; the question at every level is what to specialise in. That is the "deep" answer to maxing out at L50.

### 3.3 Point income to L10000 (G)
- Keep 1 point per 5 levels to L100 (20 points), so early play feels exactly as today (L50 = 10 + milestones).
- Then 1 point per 50 levels to L10000 (+198). Total ~218 + 6 milestones (+ more milestones, 3.6).
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

### 3.6 Milestones
Keep the six; add band milestones (first kill at L1000, first Empowered at L5000 ...) so points also arrive from play. (G, list to design.)

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
1. Count of options: nodes (46) or decisions (ranks)? See 3.1.
2. Band milestones: yes, and how many?
3. Respec price/limits, and whether Ascendant nodes can be respecced.
4. Whether card-rule nodes may touch other classes' interactions in party play (a Paladin blessing a human teammate).
