# Help-screen accuracy audit — 2026-09-11

Audited topics in `client/client.gd::show_help()` against the code: ITEMS & POTIONS, EQUIPMENT & GEAR,
LOOT & PROGRESSION, COMPANIONS, DUNGEONS, QUESTS, CRAFTING & GATHERING, MONSTER ABILITIES,
UNIVERSAL ABILITIES, TITLES & ENDGAME, SOCIAL & MISC. ~153 numeric/mechanic claims checked;
**26 entries wrong** (52 individual claims); 5 unverified. Every entry below names the code that
disagrees.

**FIXED 2026-09-11 (Opus), every claim re-verified against the code before editing**, and pinned by
`tools/probe/help_topics.gd`. Corrections to the audit itself:
- *Buff Advantage* was NOT removed: it is `DEFENSIVE_REPRIEVE_CHANCE` = **40%**, for Forcefield /
  Fortify / Iron Skin / Cloak / a landed Paralyze. The help now reads the constant.
- *Monster Gems*: the level GAP matters a lot (up to 50%), not "only 2%". Worded accordingly.
- *Gold Hoarder*: removed from the page; the constant is marked legacy-no-effect.
- **Found while fixing, and bigger than any single line:** the MAIN help page (`show_help`) was a
  23-argument positional `%` format over text containing 145 literal percent signs. It failed on
  every call and Godot returned it UNFORMATTED, so every key binding on the page read `[%s]` and
  every `25%%` showed both signs. Now named `{kN}` tokens via `String.format`. Same fault, smaller:
  the WARRIOR PATH search topic passed three unused format args and carried a literal "+11%".
- **Rage is +16% per stack** (`BARBARIAN_RAGE_DMG_PER`), not +11%: the Rampage card text and the
  Warrior page both said 11%. Both read the constant now.
- The main page also had stale Poison / Curse / Blind / Ambusher / quest / soul-gem lines; fixed.
  `stat_claims.gd` missed the Ambusher one because it matched one spelling; widened.
- In combat, the Weapon Master / Shield Guardian badge said "Guaranteed"; the roll is 50%.
- Title costs in both topics are GENERATED from `titles.gd` (`_title_costs_line`).

**Left for the owner (not fixed):** Knight's +15% damage and Mentee's +30% XP are promised but
NOTHING applies them (`get_knight_damage_bonus`, `get_mentee_xp_bonus` have no callers) - same shape
as the dead `gold_find`. Wiring them is a balance call.

The class-path topics (WARRIOR / MAGE / TRICKSTER) were checked separately against `-- cardnames`
and `-- statdesc` and match.

## Mismatches

### UNIVERSAL ABILITIES
1. **All or Nothing** lines — retired (`character.gd` erases it on load; no combat handler). Delete both lines.

### MONSTER ABILITIES
2. **Poison "30% STR/round, 35 rounds"** — `combat_manager.gd:216-217`: 1.5% of YOUR max HP per turn, 12 turns, WIS resists up to 50%, 40% apply chance.
3. **Ethereal "50% dodge"** — `combat_manager.gd:2848`: 33%. (`monster_database.gd:23` comment also stale.)
4. **Gold Hoarder "3x Valor"** — `combat_manager.gd:401`: legacy, no effect. Remove or reinstate.
5. **Blind "hides monster HP"** — nothing in the blind path touches the HP bar; message says "reduced vision". Drop the clause.

### ITEMS & POTIONS
6. **Potions "Crit/Lifesteal/Thorns"** — those are SCROLLS (`drop_tables.gd:902-904`). Move to the scroll line.
7. **"Special Scrolls: Monster Bane"** — they are POTIONS (`drop_tables.gd:26, 916-920`). +50%/3 battles correct.
8. **Cursed Coin "50% double / 50% lose half"** — `server.gd:11544-11549`: no longer functional, crumbles to dust.
9. **Skill Enhancer Tomes "-10% cost or +15% damage"** — `drop_tables.gd:956-969`: damage 15/20/25, cost 10/15/100.

### EQUIPMENT & GEAR
10. **"Repair at merchants"** — no merchant repair; Blacksmith stations (`server.gd:9413`), wandering blacksmith, Blacksmith craft.
11. **Condition ladder** — missing "Nearly Broken" (76-99%) between Damaged and BROKEN (`character.gd:1784-1799`).
12. **Master monsters "35% guaranteed drop"** — `combat_manager.gd:3495,3513`: 50%. The in-game trait line (`:11319`) says "Guaranteed" — three surfaces, three values; fix MONSTER_TRAITS too.

### LOOT & PROGRESSION
13. **Monster Gems "5+ levels above you"** — `combat_manager.gd:11531-11557`: flat 5-40% from any L50/100/200/500+ monster; the level gap adds only 2%.
14. **Affix ladder "Common 0 / Rare 2 / Epic 3 / Legendary 4 / Artifact 5+proc"** — `drop_tables.gd:4736-4741` AFFIX_COUNTS: 1/2/3/4/5/6+proc.

### TITLES & ENDGAME
15. **Every valor cost ~100x too high and written as "g"** — `titles.gd:186-330`: Summon 10, Tax 20, Knight 500+5 gems, Cure 50, Exile 100, Heal 100, Mentor 5,000+25 gems, Seek Flame 25, Restore 500, Bless 50,000+100 gems, Smite 1,000+10 gems, Guardian 20,000+50 gems. Gift 5% and cooldowns match. Generate these from `titles.gd` rather than retype.
16. **"Check Forge button"** — labelled **Fire Mt** (`client.gd:10936`).

### SOCIAL & MISC
17. **Trade "both players must be at the same location"** — `server.gd:37606-37690` has no position check. Drop the line or add the check.

### COMPANIONS
18. **Soul gem list (Frost Guardian / Storm Spirit / Nature's Bond / Void Familiar)** — none exist. `drop_tables.gd:1064-1115`: Wolf Spirit, Phoenix Ember, Shadow Wisp, Dragon Essence, Titan's Soul, Void Fragment, Celestial Spark.
19. **"Sources: dungeon completion (GUARANTEED), fishing, mining, logging"** — those are EGG sources; soul gems roll on T7+ kills at 1-3% (`drop_tables.gd:1120`).
20. **"Use soul gems from inventory"** — auto-collected into `character.soul_gems`; activate from More → Companions. Topic never mentions the egg/hatch system at all.

### CRAFTING & GATHERING
21. **Reaction-key fishing/mining text** — describes `handle_fish_start`/`_catch` which have NO callers. Live system is the 3-choice until-fail minigame (`server.gd:20984`, `handle_gathering_choice`). Rewrite.

### DUNGEONS
22. **"Into the Depths quest after First Blood"** — neither string exists. Point at Pathfinder's Trial / dynamic Dungeon Clear quests.
23. **"XP and gold per floor"** — XP once at completion scaled by floors cleared (x1.5 full clear), no valor (`dungeon_database.gd:2925-2955`).
24. **"Eggs ONLY drop from dungeons"** — rare overworld lottery exists (`OVERWORLD_EGG_CHANCE_BY_TIER`, 1/1000 T1 … 1/10M T9) plus the Pathfinder's Trial egg.

### QUESTS
25. **Kill Type / Kill Level** — LEGACY (`quest_database.gd:49-50`); live pool is DUNGEON_CLEAR / RESCUE / BOSS_HUNT / GATHER. Rescue, Gather, Deliver, Kill Tier, Exploration missing.
26. **"Rewards: XP, Gold, Gems"** — currency is Valor (`quest_manager.gd:391-393` migrates gems→valor).

## Unverified
- **"Buff Advantage: 75% chance to avoid enemy turn"** (`client.gd:34209, 34720`) — no such logic found; almost certainly removed.
- Fishing/mining/logging DROP lists — describe the dead reaction tables; the 3-choice system's per-node yields were not traced.

## Also (outside the audited topics)
- Main help text `client.gd:34266`: "Curse −25% attack" — code applies −25% DEFENSE (`combat_manager.gd:9696`). Monster Bane called a scroll there too.

## How to close this
One pass through `show_help()`, entry by entry, then extend `tools/probe/stat_claims.gd` (or a sibling)
to pin the numeric ones — title costs, affix counts, poison numbers, the condition ladder — to
their constants, so a retune breaks the check instead of the page.
