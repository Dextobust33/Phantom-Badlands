# Co-op Shared Battlefield — Combat Display Redesign (#64 cont.)

**Date:** 2026-08-27
**Context:** First 2-client co-op test ran with the flag OFF → players saw the old
solo-fanout (each in their own fight/flock, no shared visibility). Even flag-ON, the
current engine only shares the monster + turn sync; each member still renders ONLY
themselves. User wants a genuinely SHARED battle display. See memory
`project_coop_combat_shared_display`.

## Confirmed user direction (2026-08-27)
Refined the "expand the combat panel" option into a specific layout:
- **Shift the enemy ASCII art LEFT** into the currently-unused horizontal space.
- **Keep the cards centered UNDER the enemy art** (they shift left with it), plus the
  **Deck / Discard** labels next to them — same as now, just moved left.
- **In the freed right space, show up to 4 party-member sprites + their companions**
  beside them → supports a party of up to **5 total** (you + 4).
- **Round resolves as a speed-ordered animation sequence:** once ALL members have
  chosen their action for the round, the server determines order (speed), then each
  actor's animation plays in turn — player/companion/enemy lunge + FX, health bars
  update — one after another, over the course of the round.

Two combat-feedback issues flagged (affect NORMAL solo combat too):
1. **Health-bar updates feel slow** → FIXED: `_animate_bar_value` drain 1.0s → 0.45s
   (`combat_scene_panel.gd`).
2. **Floating damage numbers are hard to follow** (the ones near player/enemy sprites)
   → not sold on the current presentation; wants clearer. OPEN (see Slice 1 below).

## Current combat layout (from code audit)
`combat_scene_panel.gd::_build_scene_section_lufia()` (~L625) builds an HBox:
- **LEFT column** (stretch 1.0): combat log + YOUR player box (`_player_party_box`) +
  YOUR companion box (`_companion_party_box`).
- **RIGHT column** (stretch 1.5): monster column (`_monster_col`: HP panel + name +
  clipped ASCII art) on top + hand strip (momentum meter + 3 card cells + Deck/Discard).

Key anchors:
- Layout: `_build_scene_section_lufia()` L625–665 (HBox stretch ratios).
- Monster art: `_build_monster_column()` ~L2228, art panel clip_contents ~L2253.
- Player/companion boxes: `_build_lufia_player_box_content()` L1787,
  `_build_lufia_companion_box_content()` L1898.
- Hand strip: `_build_hand_strip()` L2704 (card cells 150×190; Deck/Discard 168×20).
- HP bars: `update_player_hp` L4290, `update_monster_hp` L4297,
  `update_companion_combat_hp` L5093; drain tween `_animate_bar_value` L5060.
- Damage popups: `_spawn_damage_label` L5810 (linger 1.95s + fade 0.75s; stack step 70px).
- Lunges: `play_player_lunge` L5515, `play_companion_lunge` L5540, `play_monster_lunge` L5680.
- Action phase: `start_action_phase` L673 / `end_action_phase` L733
  (`_overlay_retired=true` — the old floating overlay is off; FX render in-scene).

Client party plumbing that ALREADY exists (from the earlier shared-combat attempt):
- `_handle_party_combat_start` client.gd L27296, `_handle_party_combat_update` L27363,
  `_display_party_combat_hp` L27529, `_update_party_bars` L27576.
- Server sends `combat_state.members[]` = `{name, current_hp, max_hp, current_mana,
  current_stamina, current_energy, is_dead, is_fled, submitted}`.
- Member payload does NOT yet carry sprite identity (battler_id/appearance) or companion
  data — will need to extend `_party_combat_snapshot` (server.gd) to include those so the
  right-side column can render each member's sprite + companion.

## Proposed layout (to confirm)
```
 +-----------------------------------------------------------+
 |            [ ENEMY ASCII ART ]        | P2  🗡  c2         |
 |            (shifted left)             | P3  🏹  c3         |
 |                                       | P4  ✨  c4         |
 |        [ card ][ card ][ card ]       | P5  🛡  c5         |
 |        Deck: 12   Discard: 3          |                   |
 |   YOU + your companion (left/below)   |  (party column)   |
 +-----------------------------------------------------------+
```
DECIDED (user, 2026-08-27): **YOU (player + companion) stay on the LEFT** as today; the
right column shows the OTHER up-to-4 members + their companions. User rationale: a clear
separation between you and your teammates aids combat readability. Solo combat then looks
identical to today (empty right column collapses).

## Slice plan
1. **Combat-feedback quick wins (solo, low-risk, ship first):**
   - [DONE] HP-bar drain 1.0s → 0.45s.
   - Damage-number readability pass (design the clearer presentation — bigger/staggered/
     single-track? decide with user). Benefits everyone immediately + is the vocabulary the
     co-op sequence will reuse.
2. **Layout restructure (solo-safe):** shift enemy art + cards + Deck/Discard left; add a
   right-side party column container that is EMPTY/collapsed in solo (so solo is unchanged).
   Extend `_party_combat_snapshot` to include each member's battler_id/appearance + active
   companion so the column can render sprites.
3. **Speed-ordered round resolution:** client receives the resolved round (ordered action
   list) and plays each actor's lunge/FX + bar update in sequence (reuse existing lunge +
   `_animate_bar_value` + damage-number funcs). Server already resolves in speed order
   (`resolve_party_round`); send an ordered per-actor event list for the client to animate.
4. **Wire co-op + test:** flip `party_coop_enabled`, 2-client test, tune pacing.
5. **Party-invite window (QoL, independent):** replace the clunky chat/action-bar invite
   flow with a Quests-style accept popup. Can ship anytime.

NOTE: multi-session feature. Solo combat must stay pixel-identical until Slice 2+ is proven;
build the right column as additive (collapsed when party size ≤ 1).
