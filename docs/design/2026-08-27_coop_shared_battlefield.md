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

## RENDERING RULE (learned 2026-08-27)
**The `client/sprites/ascii/*.txt` class portraits (Fighter/Wizard/Paladin/…) are
RETIRED — do NOT use them for anything new.** All character rendering (player,
party members, and eventually anywhere a character is shown) uses the **battler
sprite** system: `BattlerSprite.id_from_data(data)` → `BattlerSprite.idle_texture_by_id(id)`,
tinted via `BattlerSprite.tint_color(appearance_color)`, nearest-filtered TextureRect.
Battlers are natively LEFT-facing. Monster/companion ASCII art (`MonsterArt`) is
still live — only the CLASS portrait ASCII is retired.

## RENDERING MECHANISMS TO MIRROR (learned 2026-08-27 — do NOT reinvent)
Party members MUST reuse the player's own combat rendering, not ad-hoc sizing:
- **Companion art** = a **fixed-size `Panel` with `clip_contents = true`** (like
  `_build_lufia_companion_box_content`: `_companion_portrait_bg`, `COMPACT_PORTRAIT_W/H`
  168×138) holding a **full-rect** RichTextLabel (`fit_content=false`, `PRESET_FULL_RECT`)
  at **`font_size = COMPACT_ASCII_FONT_SIZE = 1`**. THE KEY: `_is_compact_layout()` returns
  **true always** (Lufia is the only layout), so the player's companion renders at **font 1**,
  and the 168×138 box is deliberately sized so a ~75-line monster fits AT FONT 1. Use font 1
  and the art fits the box whole — no clip, matches the Kobold. DO NOT use `_companion_font_size`
  (that's the non-compact branch, unused) and DO NOT compute a font from art dimensions
  (rasterizing blurs; bigger fonts overflow + clip — hours were wasted proving this).
  Art source = the same `client._get_companion_art_lines(monster_type, name)` the player uses.
- **Member sprite gear** = `EquipmentMarkers.markers_for(equipped)` →
  `build_tint_material(markers)` (region-tint shader) on the TextureRect +
  `EquipmentMarkers.spawn_glyphs(sprite, markers, null, glyph_px)` — the SAME calls the
  player battler makes in `_show_player_battler` (combat_scene_panel.gd ~5145). Needs each
  member's `equipped` dict in the party snapshot.
- **Member sprite** = `BattlerSprite` idle frames (id_from_data → idle_0..2), tinted by
  `tint_color(appearance_color)`, animated on the shared `_battler_timer`. Members are RIGHT
  of the enemy so face LEFT (no flip).

**Therefore the REAL data the server party-snapshot must send per member** (to render
identically to the player): `battler_id`, `appearance_color`, `equipped` (for gear
markers), and companion `{monster_type, variant_color/2, variant_pattern, border_tier}`.
The admin PREVIEW uses fake samples with none of this, so gear + variant recolor won't show
in preview — they light up only once the snapshot carries real data. Wire the snapshot next.

## FINAL WORKING PARTY LAYOUT (2026-08-27 — signed off; do NOT regress)
After many failed attempts, the layout that works (user-approved):
- **Each party card mirrors the MAIN PLAYER's box + companion box at the SAME sizes**, laid
  LEFT→RIGHT in a horizontal row: `[member name + HP + resource bars] [member sprite
  portrait 168×138, flipped H to face the enemy] [companion name + HP bar] [companion art
  portrait 168×138, font 1]`. Built in `_build_party_member_card` (combat_scene_panel.gd).
- **Cards are the NATURAL 138px portrait height** (`SIZE_SHRINK`), NOT `EXPAND_FILL` sharing
  the column. Forcing them to share/shrink the column was THE core mistake — it made the
  companion art shorter than font-1 and it clipped forever. 4 cards × 138 ≈ 552px stack in
  the ~603px column (measured) — fits.
- **Companion art**: font 1 (`COMPACT_ASCII_FONT_SIZE`), fit_content label centered in a
  `CenterContainer` inside the 168×138 clip Panel (`clip_contents`). NEVER scaled (blur).
  Big monster arts (Dire Wolf/Kobold are 70-84 lines ≈ 150-210px at font 1) clip
  SYMMETRICALLY — the SAME as the player's own 138px companion box. That clip is inherent
  and acceptable; small companions fit whole.
- **Card style**: white border, black bg (`Color(0,0,0,0.88)` / `Color(1,1,1,0.9)`).
- **Main player + companion**: now ALSO one horizontal card on the LEFT (pc_card in
  `_build_scene_section_lufia`); the inner `_build_lufia_party_box` was made borderless so
  the two merge into one white/black card.
- **Fit on-screen**: party column stretch 1.2→**1.9**, right column 1.5→**1.3**, and the
  hand strip's **Deck/Discard counter hidden** (`_hand_status_label.visible=false`) to free
  ~168px. Without this the main-player-sized cards spilled off the right edge.

LESSONS (cost ~1hr of thrash): (1) NEVER scale ASCII text (blur). (2) font 1 is the min
crisp size and a FIXED height per art. (3) mirror the player's exact box sizes; don't invent
compact variants. (4) MEASURE the real node sizes before tuning — a temp `print` of column
height revealed the column was 603px (plenty) and the bug was shrinking the cards.

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

---

## 2026-08-28 — first REAL co-op fight (2 clients, flag now auto-ON)
Test: test02 (Lv9 Wizard + Kobold Helper) + test002 (Lv3 Sorcerer + Wolf Pup) vs Hobgoblin
(Lv11, HP 400 = 200 × 2 party members). Party formed, ONE shared monster, both party cards
rendered the real teammate + companion. Three defects found and FIXED (all in this pass):

1. **Member card actions silently vanished** — the log showed `▶ test02 uses Companion Card
   Wolf` with NO result under it, and test02's Kobold never attacked. NOT a message-key
   problem: server log had `Invalid access to key 'round'` at `process_ability_command`
   (combat_manager 3382) via `_party_apply_member_action`. `_party_member_view` built a
   PARTIAL solo combat dict; the solo engine reads `combat.round` (and many other keys)
   DIRECTLY, so `combat.round += 1` threw and aborted the whole ability mid-resolve —
   after the resource was spent. FIX: `_PARTY_VIEW_SOLO_DEFAULTS` seeds the FULL solo shape
   into every member view, persisted per-member in `member_states` and synced back each
   round. **Rule: the member view must stay a complete solo combat dict — any key the solo
   engine touches with dot access must exist there.**
2. **Every client read the same 2nd-person log** ("you unleash chaos…"), so nobody could
   tell who did what. FIX: the round log is now built as ENTRIES carrying BOTH voices
   (`{pid, self, other}`); `party_flatten_log(entries, for_pid)` renders per recipient — your
   own lines stay "you", teammates' are named. `_party_thirdperson()` handles possessives
   ("Your Kobold" → "test02's Kobold"), subject swaps with verb conjugation ("you unleash" →
   "test002 unleashes", "You are" → "test02 is"), object position ("hits you for 17" →
   "hits test02 for 17") and compound predicates ("and take 5" → "and takes 5"). Headers are
   2nd person for the actor ("▶ You attack") and named for everyone else.
3. **Disconnect during co-op crashed the server handler** —
   `_cleanup_party_combat_on_disconnect` was written against the LEGACY turn-based party dict
   (`dead_members` / `fled_members` / `current_turn_index`), none of which exist in the
   `party_simul` shape. Survivors could hang forever waiting on an action that could never
   arrive. FIX: a `party_simul` branch marks the member fled, and if the party was only
   waiting on them, resolves the round immediately.

CONFIRMED WORKING: monster turn now appears in the log (the `message` vs `messages` fix from
2026-08-27), per-member hands + class meters populate, party cards show real sprite/gear/companion.

## OPEN DESIGN DECISION — monster balance vs party size
Measured today: party combat scales monster **HP × party_size** and NOTHING else, while
`_party_process_monster_phase` gives the monster **ONE action per round against ONE random
member**. So for a party of N:
- Party outgoing DPS ≈ N× solo, monster HP ≈ N× solo → **fight LENGTH is already correct.**
- Incoming damage per member ≈ **1/N of solo** → the only thing broken is PRESSURE. A party
  of 4 takes a quarter of the heat each. This is why co-op feels trivial.

Options (user, 2026-08-28):
- **A. Raise monster stats.** Mathematically the worst: restoring total party damage taken
  means ~N× damage landing on ONE target per round → one-shots. Converts steady pressure
  into spikes. Rejected on its own.
- **B. One monster action per member-group per round** (hits player N or their companion).
  Restores solo pressure EXACTLY (each member takes ~solo incoming), needs no stat inflation,
  so every existing solo balance number stays valid. ~15 lines. Downside: a common Hobgoblin
  swinging 4×/round reads like a boss.
- **C. Monster PACKS — party of 4 meets ~4 monsters** (shrink monster art + HP bar to fit).
  Solves BOTH axes with no stat inflation at all: N monsters = N× HP and N actions/round
  naturally. Adds real tactics (focus-fire removes an attacker), fits the shared-battlefield
  vision, and the game already has flocks. Cost: the engine is single-monster throughout
  (`combat.monster`, targeting, per-monster DoT/CC keys, one client monster column).

RECOMMENDATION: **B now, C as the payoff.** B is a small, safe change that fixes the
trivialization immediately and keeps all solo tuning valid; C is the right end state and its
display work (smaller art, multiple HP bars) is the same work the shared battlefield needs.

### DECIDED + IMPLEMENTED 2026-08-28 — Option B (one monster action per member-group)
`_party_process_monster_phase` now loops the alive members (shuffled) and gives the monster
ONE action per member-group per round, targeting that member or their companion exactly as in
solo. No stat inflation — solo tuning stays valid. Two traps handled while wiring it:
- **Shared upkeep must tick ONCE per round.** `process_monster_turn` ticks monster
  poison/burn/bleed and counts down `monster_stunned`. Called once per member, a DoT would
  deal Nx damage per round and durations would expire N times faster. The first action does
  the upkeep; later ones run with `_PARTY_DOT_KEYS` zeroed in the view and the post-upkeep
  values restored after sync-back.
- **A stunned monster loses the WHOLE round**, not one action per member (otherwise the first
  iteration consumes the stun and members 2..N still get hit).
- A DoT tick that kills the monster during the monster phase now ends the fight as a victory
  (previously it fell through and the round continued against a 0 HP monster).

Regression harness (no clients needed): `tools/combat_simulator/coop_round_test.gd`.
Verified: 3 monster actions/round for a 3-party, bleed ticks 1x/round, per-recipient voice
correct, and a squishy member can actually die — pressure is real again.

Also fixed (SOLO-facing, found by the harness): Fighter crits rendered "you you strike the X"
— `crit_text` in `character.gd::get_class_attack_description` ended with "you " while the
template already supplies it.

### NEXT
Slice 3 (speed-ordered ANIMATION sequence) is still unbuilt: the round now resolves and logs
in speed order, but the client does not play each actor's lunge/FX/bar-drain one after
another. That is the remaining piece of the battlefield vision, plus Slice 5 (party-invite
accept window).

## SLICE 3 IMPLEMENTED 2026-08-28 — speed-ordered round playback
The round already RESOLVED in speed order server-side; what was missing was the client
animating it actor by actor. Co-op messages were already fed through the solo pacing queue
(`combat_msg_queue` → `_drain_combat_queue`), but every FX still fired on OUR OWN battler:
`_dispatch_combat_fx` classifies actors by parsing 2nd-person text ("You attack", "Your X
attacks"), and a teammate's line is 3rd person. Bars also snapped to post-round values the
instant the message arrived, so nothing drained in step with the beats.

**The fix — server-authored per-line metadata instead of text heuristics.**
- `party_flatten_meta(entries)` returns an array PARALLEL to `party_flatten_log()`:
  `{actor: member|companion|monster|neutral, actor_pid, target_pid, head, hp?}`. It rides on
  `party_combat_update` / `party_combat_end` as `message_meta`.
- `head` marks the actor's BEAT line ("▶ test002 attacks") — the client lunges there and pops
  damage/miss on the body lines that follow, so each turn reads as a distinct beat.
- `hp` is the HP snapshot AS OF THAT BEAT (`_party_hp_snapshot`): monster HP after a member's
  hit; monster + target member + target companion after a monster action. Bars drain per beat
  instead of jumping to the end state.

**Client:** `_drain_combat_queue` exposes the current line's metadata as `_party_fx_meta`,
then `_dispatch_party_fx` routes it. It returns FALSE for OUR OWN beats so the solo path runs
unchanged (our lines are still 2nd person and the solo heuristics read them correctly), and
TRUE for a teammate's — lunging their card, popping damage on their portrait, draining their
bars. While a paced round plays, `set_party_members(..., skip_bars=true)` and a deferred
`_pending_party_final_state` stop the post-round snapshot from spoiling the sequence; the
queue-empty branch settles on it so nothing can drift.

**Panel:** new party-card FX — `lunge_party_member/companion`, `show_damage_on_party_member/
companion`, `show_miss_on_party_member`, `update_party_member_hp`, `update_party_companion_hp`,
plus `_party_card_by_pid` (peer id → card, rebuilt each `set_party_members`).
`show_damage_on_monster` gained a `from_override` so a teammate's number launches from THEIR
card rather than our battler.

GOTCHAS worth keeping:
- Members sit RIGHT of the enemy and face LEFT, so they lunge **-X**.
- The companion art lives inside a `CenterContainer` (a container re-lays out its child every
  frame and fights a position tween) — lunge the **CenterContainer** (`comp_center` meta), not
  the label. The member sprite sits in a plain `Panel`, so tweening the sprite is fine.
- Lunge baselines are captured ONCE per node (`fx_baseline` meta); re-reading position on an
  interrupted tween made cards drift further left on every attack.
- `client/*.gd` are **LF**, `server/server.gd` + `shared/combat_manager.gd` are **CRLF** —
  scripted edits must match or the anchors silently fail to match.

Verified headlessly (`tools/combat_simulator/coop_round_test.gd` now dumps the beat table):
every line correctly tagged, HEAD beats on each actor, per-beat HP present, speed order
respected. VISUAL confirmation with 2 clients still pending.
