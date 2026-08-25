# Dungeon Themes — Design (task #31 dungeon-revamp arc)

Design pass 2026-08-25. Grounds the user's dungeon-revamp direction in the current
system. Design-first; implement in slices after alignment.

## User vision (verbatim direction)
- Dungeons spawn with **variety**: every monster in a dungeon shares a trait (a
  variant, and/or a color/pattern).
- The theme **carries to the egg/companion** you get there, so you know what you're
  hunting.
- A new **loot item applied to a dungeon before entry** modifies the dungeon +
  enemies within (like a PoE map/scarab or D3 keystone).

## What exists today (from the system map)
- 40+ dungeon TYPES (T1-T9) in `dungeon_database.gd` DUNGEON_TYPES. Each has a fixed
  `monster_pool`/boss `monster_type` (so a dungeon already has a monster IDENTITY —
  e.g. Goblin Caves = all goblins), `floors`, `boss`, `boss_egg`, drops, a `color`.
- A dungeon INSTANCE dict (`server.gd` ~28749) stores `dungeon_type`, `dungeon_level`,
  `sub_tier`, position, players. **No per-instance rolled flavor today.**
- Monsters spawned via `_spawn_dungeon_floor_monsters` (`server.gd` ~32783) →
  `get_monster_for_encounter` → `monster_db.generate_monster_by_name`. Variants
  (elite/corrosive/…) + Empowered mods roll PER MONSTER at uniform odds inside
  `scale_monster_to_level` (`monster_database.gd` 1538-1690) — NOT dungeon-themed.
- Enemies have **no cosmetic color/pattern**. `variant_type` drives a client ASCII
  border tint; `name_color` drives the D2 rarity name tint. Players/companions DO have
  `appearance_color` / `appearance_color2` / `appearance_pattern` (solid | gradient_up |
  gradient_down | middle | striped) — `character.gd:21-23`.
- **BUG found:** `monster_db.reapply_variant(monster, variant_type)` is CALLED at
  `server.gd:9643` (flock variant inheritance, v0.9.711) but the function **does not
  exist**. So "killing a rare variant spawns a flock of that variant" errors whenever
  it triggers (normal flocks pass `variant_type==""` and skip it, hiding the bug).

## Core concept: the THEME
Each dungeon **instance** rolls a `theme` dict at creation and stamps it on every
monster spawned inside. A theme bundles:
```
{
  id: "frostbound",
  name: "Frostbound",                 # dungeon title suffix + reward flavor
  color: "#7FD8FF", color2: "",       # cosmetic — all monsters tint the same
  pattern: "gradient_down",           # cosmetic
  trait: "" | variant_id | empowered_mod_id,   # optional MECHANICAL flavor
  reward_tint: true                   # boss egg/companion inherits color/pattern
}
```
This maps 1:1 to the three asks: shared trait+color = variety; reward_tint = themed
egg/companion; and a consumable can SET/UPGRADE the theme = the dungeon-modifier item.

## Permadeath guardrail (hard constraint from the ARPG arc)
Making EVERY dungeon monster Empowered/variant would spike lethality — the arc's hard
rule is "permadeath counterplay before density rises." **Proposed default:** a dungeon's
rolled theme is **cosmetic-only** (color/pattern + name), with **no** mechanical trait.
The harder mechanical theme (all monsters share an Empowered mod / variant, +difficulty,
+reward) is **opt-in via the Sigil item** — that's what makes the Sigil a real
risk/reward choice and keeps baseline dungeons at today's difficulty.

## Slice plan
- **Slice 0 — variant restamp fn (prereq + bugfix).** Add
  `monster_database.reapply_variant(monster, variant_type)` reusing the variant
  stat/name/ability logic from `scale_monster_to_level`. Immediately fixes the broken
  flock inheritance. Foundation for theme stamping.
- **Slice 1 — enemy cosmetic color/pattern.** Give monsters `appearance_color` /
  `appearance_pattern` (mirror the companion fields). Client `monster_art.gd` tints the
  ASCII art by them. Foundational — enemies currently have no cosmetic layer.
- **Slice 2 — dungeon theme roll + stamp + display.** Roll a `theme` at instance
  creation; stamp color/pattern (and trait if any) on each spawned monster; show the
  theme in the dungeon title/state ("Goblin Caves — Frostbound").
- **Slice 3 — theme → guaranteed themed egg/companion.** The boss egg / companion
  reward inherits the theme's color/pattern (and trait hint), so the dungeon telegraphs
  its prize.
- **Slice 4 — Dungeon-modifier consumable ("Sigil").** Applied to a dungeon before
  entry: sets/upgrades the theme, bumps difficulty (shared Empowered mod on all
  monsters), and boosts reward (guaranteed themed egg + bonus card/loot). New endgame
  loot sink; the opt-in path to hard themed dungeons.

## Decisions locked (user, 2026-08-25)
1. **Baseline = cosmetic theme.** BUT a dungeon can **rarely** roll a MECHANICAL theme
   (all monsters share an Empowered mod / are harder). Hard requirement: a **clear
   pre-entry WARNING** so players aren't surprised by a harder themed dungeon. The
   Catalyst forces/upgrades the mechanical theme on demand.
2. **Build now: Slice 0 (reapply_variant bugfix) + Slice 1 (enemy cosmetics).** These
   are the safe foundation. HOLD slices 2-4.
3. **Modifier item name = "Catalyst"** (e.g. "Frostbound Catalyst"). Note: reuses the
   existing "Ascension Catalyst" naming family in the fusion system.

## ⚠ BROADER REVAMP DISCUSSION STILL OWED (user, 2026-08-25)
User: "there are more things we need to discuss regarding dungeons before you go off
building a bunch of things. This is supposed to be a dungeon revamp so it will require
planning and discussion." → After shipping slices 0+1, DO NOT proceed to slice 2 (theme
roll) or beyond. Open a broader dungeon-revamp planning discussion first: structure,
floors, pacing, bosses, rewards, entry/warning UX, what "revamp" means to the user
beyond themes. Themes are one strand of a larger revamp.
