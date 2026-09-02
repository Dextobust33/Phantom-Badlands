# Phantom Badlands — Master Backlog

**The single ordered to-do list.** Keep it current: when work finishes, move it to *Recently
shipped*; when a new direction is agreed, add it in the position its dependencies allow.

Ordering rule: **each item is placed so its inputs are settled first** — measurement before
tuning, data model before UI, combat numbers before anything sized against them. Working out of
order is what forces revisits.

> Detailed design and history live in `docs/design/` and in the assistant project memory.
> This file is the ordering and the status.

---

## In progress

### 1. Party mechanics — server pass
- [x] Leader **rotation** after each combat (default) + alternate **control modes** (fixed / rotate)
      — `Lead: Rotate / Lead: Fixed` toggle in the Party menu. Rotation walks a stable
      `rotation_order`, not `party.members` (which `_transfer_leadership` reorders new-leader-first,
      so rotating over it would ping-pong between two players). Verified fair for 3 members
- [x] Reward policy: **DUPLICATE** — gathering materials and job XP are copied in full to every
      member. Wrapping `_add_gathering_reward` covers every gathering path at once instead of
      changing ten call sites. **Crafting shares XP only** — duplicating the crafted item would
      mint N items from one set of materials
- [x] Rotation survives membership **churn** — leavers are dropped from the order, joiners are
      added, and rotation skips anyone dead/offline/departed. Verified: leavers never lead again,
      joiners get turns, no stale ids
- [x] **Leadership transfer verified** — with 3 members, the leader dying hands leadership to a
      survivor instead of disbanding. Needed a scenario where ONLY the leader is at 1 HP: in a
      lethal zone the others die first, the party drops to two, and it disbands instead
- [ ] Live test of rotation + duplicated rewards (`party3`, `gather_*`, `craft_ready`)

*Rotation and rewards ship together: both edit party state and `_end_party_combat_all`, so
splitting them means editing and re-testing the same code twice.*

---

## Next

### 2. Party UI (after 1 — rotation changes leader semantics and action-bar states)
- [ ] Target picker: use items **on teammates** (click a party card; number keys as a supplement)
- [ ] Buffs castable on teammates (forcefield on someone else). Server-side, ability effects
      currently apply to `combat.character`, the caster — cross-targeting is a real change
- [ ] Quests-style **invite/accept window** (the current chat/action-bar flow is clunky)
- [ ] **Watch a teammate's minigame.** Gathering (scratch-off) and crafting (reveal panel) are
      single-player panels driven by a payload sent to the actor alone; the rest of the party
      only sees the result line. Since rewards now DUPLICATE, everyone is receiving what is being
      revealed, so watching it is meaningful. Needs the server to broadcast the payload plus each
      reveal to party members, and a read-only mode on both panels

### 3. Simulator upgrade — **blocks all balance work**
- [ ] Teach the sim to spend **abilities and resources**. It drives real combat code but uses
      basic attacks only, which is why the resource-economy flaw and the low-level regression
      both slipped through
- [ ] Calibrate `make_char` against **real saved characters** (it inflates stats)

### 4. Balance pass (after 3)
- [ ] **Magic Bolt flat curve** — measured ~21x per mana at L5 vs ~27x at L20, while monster HP
      scales far faster. Lowering the coefficient only moves where it flips from absurd to
      useless; damage-per-mana has to scale on the same curve as monster HP
- [ ] Ability cost model / resource economy (costs flat while pools scale)
- [ ] Anti-abuse items that **never landed**: Forethought and Recharge still exist, no mitigation
      cap, no stun DR. Related user direction: remove blue "skip the enemy turn / refund
      resources" utility cards
- [ ] Equipment vs race vs class, compared **against each other** rather than in isolation
- [ ] How far players can actually push: win rate vs monster-level delta

### 5. Monster packs (a party of N meets ~N monsters)
Last of the core combat work: packs multiply monsters per fight, so sizing them before 4 fixes
per-monster numbers guarantees a redo.

---

## Dungeon arc

*`docs/design/dungeon_revamp.md` is the master design. Hard constraint throughout: every dungeon
stays **solo-possible**; a party is a force multiplier, never a requirement.*

### 6. Dungeon F — party in dungeons (north star, most architectural)
- [ ] Party **movement** in a shared instance
- [ ] Party combat inside dungeons on the deck system
- [ ] Follower-finishes-boss reward case; per-player equipment/chest loot

*Placed here because it builds on 1 and 2. Doing it earlier means touching party code a third time.*

### 7. Dungeon B — loot / progression / discovery
- [ ] **Dungeon Atlas / Codex** — hub, quest board, what-drops-where, uniques page.
      This is ONE item; it was previously tracked in three separate memos as three tasks.
      Reveal is **hint-based discovery with progression**, not show-all: entering or clearing
      gives full detail, spotting a D tile gives partial, a rumour gives a hint. Hooks into the
      existing rumour, threat and discovery tracking
- [ ] Signature drop per dungeon
- [ ] Broader scattered loot (runes / gear / scrolls, tier-scaled)
- [ ] Companion **Tier-RANK** variety

### 8. Dungeon A — themes (slices 2-4)
- [ ] Theme roll / stamp / display; theme to guaranteed themed egg or companion
- [ ] "Sigil" opt-in modifier consumable
- [ ] **Preserve** both random special-trait dungeons AND the Catalyst/Sigil opt-in — the Atlas
      and meta work must not delete either

### 9. Dungeon E — presentation
- [ ] Zoom the dungeon view in
- [ ] **Sprites** for chests, traps and floor drops instead of ASCII glyphs (unused sheets in
      `client/sprites/battlers/tf_svbattle/singleframes/`)
- [ ] Stop drawing **walls as tiles** — render non-traversable space as void (Azure Dreams style)
- [ ] Rooms **farther apart**, longer corridors (still too cramped after C3a)

### 10. Dungeon D — bosses (after 4, so boss damage is sized against corrected numbers)
- [ ] Real phases, telegraphs and adds. **Telegraph counterplay is mandatory** — no unavoidable
      damage

---

## Then

### 11. Realm meta-loop
- [ ] Reorient **questing onto dungeons** (clear / rescue / boss-hunt / gather). The quest types
      already exist; the work is generation and surfacing, not new types
- [ ] Real **sinks for excess eggs and companions**: shops that buy and sell, breeders, trainers,
      fusers (fusion exists — expand), companion **tasks**
- [ ] Living world: rework posts, companions around posts, threats woven in

### 12. Engagement / minigame variety
- [ ] Prize Shuffle redesign: gathering and crafting slices (combat slice shipped)
- [ ] Port the Chain / Mystery / Trap mechanics to gathering and crafting
- [ ] Trap chests, Mimic chest variant, 2 remaining dungeon-exclusive consumables

---

## Independent — slot in any time (no dependencies)
- [ ] Card market live list-to-buy smoke test (built, never exercised end to end)
- [ ] Launcher revamp + in-game feedback inbox
- [ ] UI-scale registration for remaining elements (action bar, inventory, market, crafting...)
- [ ] Unspent stat-point "+" badge (players forget they have points)
- [ ] Combat default layout at 1080p (cards overlap the monster art)
- [ ] Companion cosmetics: ASCII border + shadow layer (data layer already shipped)
- [ ] Merchant/market **baseline NPC stock** — merchants only equalise player listings, so
      off-circuit posts stay bare
- [ ] Tutorial + starter quest chains for a zero-gear character
- [ ] Patreon + Founder title (implementation planned, awaiting greenlight)
- [ ] Item variety — duplicates should be rare
- [ ] Ability-card level-up progress fill, draggable action bar, plain-language skill text
- [ ] Salvage preview: tell the player what they get before salvaging
- [ ] Variant Imprint Atlas page (Sanctuary)
- [ ] Bug-reporting system: end-to-end test on production (shipped, never verified live)
- [ ] ARPG pillar 5: endgame rift runs

## Hard-deferred (documented reason — revisit only if the reason changes)
- Visible roaming entities (performance gate)
- Full ability mastery as a progression vector (multi-session arc)
- Group raids
- Full mentor matching
- Biome-specific mechanics (movement, weather, biome-locked monsters and resources)
- Multiple saved decks, swap-on-the-fly, true drag-and-drop (needs server work)

## Watch items (not tasks — things that must not regress)
- **The from-source client remembers the last host** and all clients share one settings file, so
  a single manual connect to production silently sends later local test runs to the LIVE server.
  The harness forces `--server=localhost` and the client prints its target; don't remove that
- **Permadeath may change** — do not harden "death is permanent" into copy or design pillars
- **Archive with discussion** — removing game elements is allowed, but discuss first; improving
  beats removing. Crafting was flagged as "not in a good spot at all"
- **Early-game survivability** — resource cost scaling still open; starter weapon at creation
  deferred pending playtest

---

## Recently shipped
- **v0.9.739** — co-op combat you can follow (one animation clock), party items, party permadeath,
  login sprite offset, relog full-heal fix, 2-client test harness (`tools/test_setup/`)
- **v0.9.738** — real co-op party combat (shared fight, party cards, per-actor playback)
- **v0.9.735** — card arc: dungeon-exclusive cards, card market, class roster pass, FPS cap
