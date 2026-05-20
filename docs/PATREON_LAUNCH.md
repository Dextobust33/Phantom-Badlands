# Patreon Launch — Step-by-Step Guide

**Last updated:** 2026-05-20 (v0.9.578 ship)
**Status:** In-game infrastructure ready. External Patreon page not yet created.

This is the runbook for actually launching the Patreon page. The in-game side (titles, tier persistence, admin fulfillment) shipped in **v0.9.578**. Everything below is the off-platform work plus the small in-game additions that pair with the live URL.

---

## What's already done (in-game)

You can skip this section if you trust the v0.9.578 release notes. Otherwise:

- ✅ Three new chain titles defined: `patreon_supporter` (green), `patreon_founder` (gold), `patreon_patron` (purple) — visible to wear via `/set_title`.
- ✅ Account-level `patreon_tier` int field stored alongside Sanctuary data (0=None, 1=Supporter, 2=Founder, 3=Patron).
- ✅ Auto-sync at character load — when a supporter logs in, their title appears in `earned_titles` automatically.
- ✅ Fulfillment flow via `/admin → Patreon` sub-page (4 buttons, Tier 0-3, targets nearest online player within 5 tiles).
- ✅ Supporter gets a private thank-you chat line when tier is set to > 0.
- ✅ Hard rule baked in: cosmetic-only, no combat advantage.

Source files (for reference, don't need to touch):
- `shared/quest_database.gd` — title definitions
- `server/persistence_manager.gd` — tier storage
- `server/server.gd` — sync logic + admin handler
- `client/admin_panel.gd` — fulfillment UI

---

## Step 1 — Create the Patreon account

**Time estimate:** 10-15 minutes.

1. Go to https://www.patreon.com/signup and create an account using whichever email you want associated with the project.
2. When prompted "What are you creating?" pick **"Games"** as the category.
3. Page name: `Phantom Badlands` (or `Phantom Badlands Dev` — your call).
4. URL slug: `patreon.com/phantombadlands` if available. Check at https://www.patreon.com/[slug-you-want].
5. Skip the avatar/banner upload for now — you can add them later from the dashboard.

---

## Step 2 — Write the About page

**Time estimate:** 30-45 minutes.

Patreon's "About" section is the elevator pitch. Keep it short and player-focused.

**Suggested content** (edit freely):

> # Phantom Badlands
>
> Phantom Badlands is a free, open text-based multiplayer RPG built solo in Godot. Multiplayer party combat, procedural world, nine classes, hundreds of companions, fusion mechanics, player-owned settlements.
>
> **The game stays free, forever.** Patreon supporters get cosmetic recognition + small quality-of-life perks. There is no pay-to-win in Phantom Badlands. Ever.
>
> Your support pays the Hetzner game server (~$7/mo) and the Claude AI subscription that helps me ship updates at the pace I've been holding (10+ releases on a good night). That's it. No agency. No team. One developer + occasional AI assistance + your support keeping the server lights on.
>
> Pick a tier below if you want to chip in. Or just keep playing — that's enough.

**Hard rules to keep in the page text** (so you don't drift later):
- Game is and stays free.
- Cosmetic + small QoL only.
- No combat advantage.

---

## Step 3 — Configure the three tiers

**Time estimate:** 20 minutes.

In the Patreon dashboard, set up three reward tiers matching the in-game scaffolding:

### Tier 1 — Supporter — $5/month

**Title text:** `Supporter`
**Description:**
> A green `[Supporter]` title in-game, visible in chat and the player list. Pays the server bill for ~2 weeks. Thank you.

### Tier 2 — Founder — $10/month

**Title text:** `Founder`
**Description:**
> A gold `[Founder]` title in-game. **+1 extra Sanctuary registered companion slot** (one more death-resistant companion you can keep across permadeath). Pays the server bill for a month. Thank you.

### Tier 3 — Patron — $20/month

**Title text:** `Patron`
**Description:**
> A purple `[Patron]` title in-game. Founder's +1 Sanctuary slot, PLUS **the Sanctuary kennel capacity tier 1 unlock is free** (saves ~5000 Baddie Points). Pays the server bill + a chunk of the AI tooling that keeps updates flowing. Thank you.

> ⚠ **Note**: as of v0.9.578 only the titles are wired. The +1 slot (T2) and kennel-tier (T3) tame-QoL bonuses ship in v0.9.579 — see "Step 6: Verify in-game perks land" below.

---

## Step 4 — Set up reward fulfillment workflow

**Time estimate:** 5 minutes (just understanding the flow).

Fulfillment is **manual** for V1. When someone pledges:

1. Patreon emails you their pledge notification.
2. You ask them (via Patreon DM or your preferred channel) for their **in-game character name**.
3. Wait for them to log in. Check the player list or `/who` to confirm they're online.
4. Walk up to them in-game (within 5 tiles).
5. Open `/admin → Patreon`.
6. Pick their tier (Tier 1, 2, or 3).
7. Their title appears immediately. They get a private thank-you chat line.

**Why manual?** Patreon webhook integration would automate this but it's overkill while the supporter count is small. When manual fulfillment becomes painful (say, ≥30 active supporters or you're handling >5 changes a week), the webhook is the next infra step.

**If a supporter cancels:**
1. Patreon notifies you when a pledge ends.
2. Same flow but pick **Tier 0** to remove the title. They keep their character + everything else — they just lose the cosmetic tag.

---

## Step 5 — Add the Patreon URL to the game

**Time estimate:** 10 minutes (one small client release).

Once the Patreon page is published and you have the URL, add a `/patreon` chat command that surfaces the URL in-game.

**What to do:**

1. Edit `client/client.gd`:
   - Add `"patreon"` to the `command_keywords` array (around line 21287).
   - Add a case in the `process_command()` match statement (around line 22500-ish, near the other command cases) that prints the URL + a brief description.
2. Bump VERSION.txt → 0.9.580 (or whatever's next).
3. Add a changelog entry mentioning the Patreon launch.
4. Export client, create release, push.

Skeleton for the chat command:

```gdscript
"patreon":
    display_game("[color=#FFD700]✦ Phantom Badlands on Patreon[/color]")
    display_game("[color=#9ACD32]https://www.patreon.com/<your-slug>[/color]")
    display_game("[color=#888888]The game stays free — Patreon support pays the server + AI tooling. Cosmetic perks + small QoL only, never combat advantage.[/color]")
```

---

## Step 6 — Verify in-game perks land

**Time estimate:** 15-30 minutes (test session).

Before you announce the Patreon publicly:

1. Make a test character.
2. From your admin account, walk up to the test character and set Tier 1 (Supporter) via `/admin → Patreon → Tier 1`.
3. Confirm the green `[Supporter]` title appears in `earned_titles` (visible via `/titles`).
4. `/set_title patreon_supporter` and check it renders in chat correctly.
5. Repeat for Tier 2 + Tier 3.
6. Set back to Tier 0 and confirm the title is removed cleanly.
7. **If v0.9.579 has shipped:** also confirm the +1 Sanctuary slot (T2) and free kennel-tier (T3) are active.

If anything is broken, that's a `/bug` report.

---

## Step 7 — Announce

**Time estimate:** 30-60 minutes (announcement copy + posts).

Channels to consider:
- In-game `/announce` server message (post a clear line in chat for online players)
- Discord/community channels if any
- GitHub release notes for the version that adds `/patreon`
- The game's website (https://phantombadlands.com)

Tone: low-pressure. Lead with "the game stays free" + "this is how it stays free."

Example announcement:

> Phantom Badlands now has a Patreon page: patreon.com/phantombadlands
>
> **The game stays free.** Patreon supporters get a cosmetic title (Supporter / Founder / Patron) and small QoL perks. No combat advantage, ever.
>
> Your support pays the Hetzner game server + the Claude AI tooling that keeps updates shipping. If you like the game, chip in. If not, just keep playing — that's enough.
>
> Type `/patreon` in-game for the link.

---

## Step 8 — Maintenance ongoing

**Time per supporter:** ~2 minutes.

- New pledge → DM for character name → fulfill at next overlap.
- Tier change → adjust via `/admin → Patreon`.
- Cancellation → set to Tier 0.

When fulfillment gets painful, look at the Patreon webhook docs: https://docs.patreon.com/#webhooks

The webhook would let the server auto-flip the tier on pledge events. ~2-3 hours of work to wire when you decide to do it.

---

## Why this design (rationale)

For reference if you want to revisit choices:

- **Cosmetic + tame QoL only**: pay-to-win is a community killer in any game, and especially in a small one. Better to undermonetize than to compromise the community.
- **Manual fulfillment**: keeps the launch cost near-zero. The webhook can come later.
- **Admin panel UI, not chat command**: per CLAUDE.md, new admin actions go through `/admin`, not new chat shorthands.
- **Nearest-player targeting**: avoids needing a text-input field in the visual admin panel. Walk up to the supporter, click the tier. Cleaner than typing a username.

Full design rationale + future-extension notes: `~/.claude/projects/.../memory/project_patreon_founder.md` (Claude's memory store).

---

**You're done.** Push the Patreon page live whenever you're ready. The in-game infra is waiting.
