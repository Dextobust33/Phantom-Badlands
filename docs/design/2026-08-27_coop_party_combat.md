# Co-op Party Combat rebuild (#64) — Design Proposal

**Date:** 2026-08-27
**Task #64:** Rebuild shared party (co-op) combat on the card system.

## Why / current state
The old shared party combat (`combat_manager.start_party_combat` /
`process_party_combat_action`) still exists but is DISABLED — v0.9.732 routed party
encounters to per-member SOLO card battles (`_start_solo_combat_for`) because the old
shared version was broken: members saw *different* monsters, had *no cards* (it predates
the card system — used slot-based `CombatAction`), and one kill ended everyone's fight.
Parties currently travel + group together but fight solo. #64 = real co-op: one shared
monster, everyone fights it together, using their decks.

## What we SALVAGE vs REBUILD
- **Salvage:** the turn-queue skeleton (`current_turn_index` round-robin → monster phase),
  monster HP × party size, `active_party_combats` / `party_combat_membership` tracking,
  target weights, per-member `member_states`.
- **Rebuild:** the per-member TURN must run through the CARD system (draw a 3-card hand,
  play cards) instead of the retired slot-based `CombatAction`.

## Proposed model

### Turn structure — sequential round-robin
Round = member 1 acts → member 2 acts → … → **monster phase** → repeat. On a member's turn
they draw their own hand of 3 from their own deck and play as in solo (the engines —
Momentum / Focus / Combo — are per-member). One shared monster; when anyone damages it, all
see the same HP. Fixes "different monsters" + "one kill ended both."

### Card integration — per-turn "combat view"
The ability handlers (`process_ability_command`, `process_attack`, etc.) operate on a `combat`
dict of shape `{character, monster, <state>}`. For a member's turn we build a **view** =
`{character: acting_member, monster: SHARED_monster, <that member's member_state fields>}`,
call the existing solo handler on it, then merge the member_state back and keep the shared
monster HP. This REUSES all card logic instead of reimplementing it — the key to not
re-breaking combat.

### Monster phase
Monster acts once per round (or per its `actions_remaining`), targeting a random ALIVE member
weighted by threat (`target_weights`). Uses the existing monster-turn logic against the chosen
member's view.

### Death / flee / disband
Dead member → skipped in the queue; all dead → party wipe (existing corpse flow per member).
Flee → that member leaves the fight (others continue). Disband mid-combat → convert remaining
to solo or end gracefully (edge case).

### Rewards (fork — see below)
On monster death, propose **each surviving member gets FULL XP + their own independent loot
roll** (co-op should feel rewarding, not split) — the monster was HP-scaled, so it's earned.

### Client UI (the biggest piece)
Shared combat view: the monster + a compact **HP bar per party member** + a **turn indicator**
("Your turn" / "Waiting for <name>…"). On your turn, your normal hand + action bar; off your
turn, a read-only view of the shared fight updating live. Reuses the combat scene panel with a
new party-members row + turn banner.

## Build slices (multi-session feature — this won't all land at once)
1. **Server turn engine** — round-robin + monster phase routing each member's turn through the
   card handlers via the per-turn view. (No new UI yet; verify via logs / 2 headless peers.)
2. **Client co-op combat UI** — member HP row + turn indicator + read-only off-turn view.
3. **Rewards + edge cases** — death/flee/disband mid-combat, shared victory rewards.
4. **Polish + playtest** — pacing, message clarity, re-enable via the party path in
   `trigger_encounter` (replacing `_start_solo_combat_for` for parties).

## DECISIONS (user, 2026-08-27)
1. **Turn model: SIMULTANEOUS submit-then-resolve.** Each round, every alive member submits ONE
   action (play a card / basic attack / item / flee). When all alive members have submitted, the
   server resolves all member actions in **speed order** (faster acts first — fair + readable),
   THEN the monster acts (threat-weighted target). New round → redraw all hands → submit again.
   A per-member `submitted_this_round` flag gates the resolve; a member who hasn't submitted blocks
   the round (small parties; add an optional ready-timeout later if AFK is a problem).
2. **Rewards: FULL XP + own independent loot roll for each surviving member.**
3. **Scope: FULL rebuild** — shared combat + per-member HP bars + turn/submission indicator +
   live view as others submit.

## Slice plan (revised for simultaneous)
1. **Server engine (Slice 1, START NOW):** party-combat STATE for simultaneous submission +
   submit handler (`handle_party_action` records a member's queued action) + `_resolve_party_round`
   (speed-ordered member resolution via the per-turn card view → monster phase → redraw). Built as
   NEW code paths, NOT yet wired into `trigger_encounter` (so live solo combat is untouched until
   the whole thing is proven).
2. **Client co-op UI:** member HP row + "submitted / waiting" indicator per member + live resolve
   log; your hand stays interactive until you submit, then locks until the round resolves.
3. **Rewards + edge cases:** death/flee/disband mid-round, all-submitted detection, party wipe,
   shared-victory rewards (full XP + own loot each).
4. **Polish + playtest**, then flip the party branch in `trigger_encounter` from
   `_start_solo_combat_for` to the new engine.

NOTE: this is a multi-session feature; Slice 1 is a foundation, deliberately un-wired so it can't
regress live combat mid-build.

## STATUS
- **Slice 1 DONE** (commit 60b3a3a): state + submit-gating + per-member decks.
- **Slice 2 DONE + HEADLESS-VERIFIED:** the resolution engine. `resolve_party_round(leader_id)`
  resolves members in speed order via a per-member "combat view" (`_party_member_view`) fed to the
  real solo card handlers (`process_ability_command` / `process_attack`), with two OPT-IN guards
  that make the reuse safe: `suppress_monster_turn` (member cards don't trigger per-card
  retaliation) + `suppress_victory` (a killing blow flags `party_kill` instead of running solo
  rewards). Then `_party_process_monster_phase` runs the monster ONCE vs a random alive member.
  Verified via `real_combat_sim._verify_party_combat`: 2 members both damage the SHARED monster,
  the monster hits exactly ONE member, the round advances + hands redraw. Solo combat untouched
  (guards are opt-in). Still UN-WIRED — `trigger_encounter` routes parties to solo until Slice 4.
- **Slice 3 DONE (server side):** `_handle_party_combat_command` rewritten for the simultaneous
  flow — a member's command → `submit_party_action`; when `_party_all_submitted`, → `resolve_party_round`
  → `_broadcast_party_update` (round messages + a live `_party_combat_snapshot`: monster HP, each
  member's HP + submitted/dead/fled, round) to ALL members; `_end_party_combat_all` on combat_ended.
  Snapshot field names aligned to what the client's EXISTING party-combat UI (`_handle_party_combat_update`
  / `_display_party_combat_hp`) already reads, so no client rewrite needed. Per-recipient `is_your_turn`
  maps to "you haven't locked in yet." Still UN-WIRED (the old handler was dead code — nothing populates
  `party_combat_membership` until the start is wired).
- **Slice 4 (next):** flip `trigger_encounter`'s party branch from `_start_solo_combat_for` to
  `start_party_combat_simul` + send `party_combat_start` to all members (puts clients in party-combat
  mode); shared victory rewards (full XP + own loot each); death/flee/wipe/disband edge cases; then a
  2-CLIENT live test (co-op needs two connected players to validate the full loop).
