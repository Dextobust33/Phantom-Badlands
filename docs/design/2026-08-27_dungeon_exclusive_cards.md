# Dungeon-Exclusive Cards (#38) — Design Proposal

**Date:** 2026-08-27
**Task #38:** Replace the dungeon "copy-drop" with genuinely dungeon-EXCLUSIVE cards.
**User direction:** build cross-class variety through companion + dungeon-exclusive cards,
"if we balance those correctly." Careful, no abusable loops.

## Current state ("copy-drop")
`server/server.gd::_roll_dungeon_card_reward` (v0.9.679): on dungeon completion, a
tier-scaled chance (5% + 2%/tier, cap 30%) grants **+1 copy of an ability the player already
has** (weighted toward used abilities, capped at MAX_ABILITY_COPIES=3). It feeds deckbuilding
but adds ZERO new variety — you just get a 2nd/3rd copy of a card you already run.

## The opportunity — reuse the companion-card engine
Non-class cards already exist and are fully data-driven:
- Prefix-routed: `combat_manager` routes `companion_card_*` ids to `_process_companion_card_ability`.
- Data-driven: `DropTablesScript.COMPANION_CARD_DATA` defines each card's `kind` + values;
  the processor already implements kinds **strike / DoT / debuff / rage (dmg buff) / guard (DR) /
  focus (crit) / shield / heal / resource / loot**.
- Stored in `combat_deck_collection`; displayed by the existing card UI; copies capped.

**Dungeon cards = the same pattern with a `dungeon_card_` prefix + a `DUNGEON_CARD_DATA` table.**
Almost no new combat plumbing — just a data table, a prefix route, and a grant path.

## Proposed design

### 1. Cards are UNIVERSAL (any class can run them)
This is the whole point — cross-class variety. A Warrior running a poison DoT, a Mage running a
lifesteal strike, etc. They cost a modest amount of the player's own class resource (same as
companion cards), so no new resource to balance.

### 2. Themed to dungeon archetype (flavor + a reason to run specific dungeons)
Each dungeon TYPE has a signature card, so clearing a Vampire Crypt can drop the vampiric card,
etc. (Falls back to a tier-weighted pool for dungeons without a themed card.)

Starter set (all reuse EXISTING kinds → low risk; all situational sidegrades, never strictly
better than a class finisher):

| Card | Dungeon theme | kind | Effect (scales with usage tier) |
|---|---|---|---|
| **Venom Fang** | Spider Nest | DoT | Strike + stacking poison (% of hit/turn) |
| **Plague Bloom** | Plague Graveyard | debuff | −monster DEF + light DoT |
| **Blood Pact** | Vampire Crypt | heal-on-hit | Strike that heals % of damage dealt (bounded by hitting — NOT a free heal) |
| **Bone Ward** | Forgotten Crypt | shield | Absorb shield (scales with Attack) |
| **Sunder** | God Slayer Arena | strike (armor-pierce) | Damage ignoring a % of monster DEF |
| **Frost Trap** | any ice dungeon | debuff | −enemy accuracy (one attack, like Frost Nova) |
| **Entropy Surge** | Entropy End | strike | Damage + small self-risk (chaos flavor) |
| **Soul Harvest** | high-tier generic | loot | Strike + bonus gems/XP on kill |

### 3. Grant mechanic — replace the copy-drop
`_roll_dungeon_card_reward` becomes `_roll_dungeon_exclusive_card`:
- Same tier-scaled chance. On a hit, drop the dungeon's THEMED card (or a tier-appropriate pool
  pick) as **+1 copy** into `combat_deck_collection`.
- **Permanence:** granted PERMANENT on drop (dungeon cards are rare and earned by a full clear —
  no "use N times to keep" grind like companion loaners). Copies still capped at 3.
- Keep a small fallback: if the player already has 3 copies of the themed card, fall back to the
  old copy-drop (so the reward never whiffs).

### 4. Balance / anti-abuse guards
- No card restores a resource; none grant an extra turn or turn-skip. (Same hard rules as the
  Mage pass.)
- Blood Pact heals only a fraction of *damage actually dealt* → bounded by connecting, no loop.
- Damage/DoT values tuned at or below comparable class cards; cost = modest class resource so
  they compete for the same economy.
- Copies capped (3); universal so no class-specific power spikes.
- Sim-verify: run the difficulty audit with a dungeon card forced into each class's deck; confirm
  win-rate band unchanged.

## Open decisions (need your call)
1. **Themed-per-dungeon vs flat tier pool?** (Proposal: themed, with a pool fallback.)
2. **Permanent-on-drop vs use-to-keep?** (Proposal: permanent on drop — they're rare clears.)
3. **Fully replace the copy-drop, or keep copy-drop as a rarer secondary roll?** (Proposal:
   replace as the primary; copy-drop becomes the "already maxed" fallback.)
4. **Starter set size** — 8 as above, or start smaller (3–4) and expand?

## Rollout
1. `DUNGEON_CARD_DATA` table + `dungeon_card_` prefix route (mirror companion cards).
2. Grant path (`_roll_dungeon_exclusive_card`) + completion message.
3. Client display (name/color/description/preview — reuse companion-card display path).
4. Sim-verify each card in-band, then release.

## STATUS — IMPLEMENTED (local, UNRELEASED) 2026-08-27
Decisions (user): themed-per-dungeon, PERMANENT on clear, copy-drop = fallback; start with 4.

Slice-1 cards (all reuse existing companion-card `kind`s → zero new combat logic):
| id | name | dungeon | kind |
|----|------|---------|------|
| dungeon_card_venom_fang | Venom Fang | spider_nest | poison (DoT) |
| dungeon_card_crimson_draught | Crimson Draught | vampire_crypt | lifesteal |
| dungeon_card_bulwark_of_bone | Bulwark of Bone | forgotten_crypt | shield |
| dungeon_card_executioners_edge | Executioner's Edge | god_slayer_arena | execute |

Implementation:
- `drop_tables.gd`: `DUNGEON_CARD_DATA` + `dungeon_card_id_for_dungeon` + generalized helpers
  (`get_card_data_by_id` / `card_display_name` / `card_category` / `is_data_card_id`) handling BOTH
  `companion_card_` and `dungeon_card_` prefixes.
- `combat_manager.gd`: routes `dungeon_card_` to the SAME `_process_companion_ability`; command
  whitelist + `_ability_display_name` updated.
- `character.gd`: `get_all_available_abilities` surfaces owned dungeon cards (count>0).
- `server.gd`: `_roll_dungeon_card_reward(character, tier, dungeon_type)` grants the themed card
  PERMANENT (first copy set directly, bypassing add_ability_copy's accessibility gate), falls back
  to the copy-drop when no themed card / already 3 copies. Distinct "★ DUNGEON CARD EARNED!" banner
  (solo + party follower paths).
- `client.gd`: display name / category (distinct ◆ glyph, amber-offense / teal-buff banner) /
  description / pip value all extended to `dungeon_card_` via the generalized helpers.
- Sim (`_verify_dungeon_cards`): all 4 map correctly, appear in the pool after grant, and cast
  cross-class without error (Fighter cast poison/lifesteal/shield/execute). In-band by construction
  (reuse companion power values). Difficulty audit still clean.

Universal (any class) → delivers the cross-class variety the user wanted from dungeon cards.
Needs a FULL client+server release. Phase-2 expansion: more cards (wolf_den, plagued_graveyard,
entropy_end, etc.), armor-pierce kind, boss-only cards.
