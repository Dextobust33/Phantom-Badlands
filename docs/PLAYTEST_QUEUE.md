# Playtest queue — what is waiting on hands at the PC

Everything here is **committed to master and NOT released**, or released but unconfirmed. Each
item has a one-command setup and a short list of what to look at. Written 2026-09-10.

**Run one command, look at the listed things, tell me pass/fail.** If several pass, they can go
out as one release rather than several.

> Setup is always `python tools/test_setup/run.py <scenario>` from the repo root. It applies the
> save state, starts the server, and logs the clients in. `--list` shows every scenario.

---

## 0. RELEASE CHECK — six unverified fixes, one dungeon run  *(do this one)*

Everything below items 1-3 has passed. These six landed **after** that feedback and have never
been seen running. One command, one dungeon, roughly ten minutes.

```bash
python tools/test_setup/run.py release_check
```

Parked on a dungeon entrance with food, the cycle-value cards, lots of HP, and an egg **three
steps from hatching** so it pops underground rather than never.

Enter via **Admin > Items > Enter T1 Dungeon (instant)** — not Admin > World.

- [ ] **A. Egg hatch underground.** Walk 3-4 steps. A companion hatches. **The dungeon floor must
      stay on screen** — the hatch notice belongs in the run log on the right. (It used to blank
      the whole canvas.)
- [ ] **B. Props under theme-tile glyphs.** Look at the coloured letter tiles (mud, moss, webbing
      — whichever this dungeon uses). Some should now have a pebble or twig **behind** the letter,
      at about the same one-in-seven rate as plain floor. Before, glyph tiles were always bare.
- [ ] **C. Card damage is hoverable.** Start a fight, play **Venom Fang**. Hover its damage
      number in the combat log — it should show a breakdown, and a floating number should appear
      over the monster. You reported this dead last time.
- [ ] **D. A fully-absorbed hit says so.** Get a ward up (play or cycle **Bulwark of Bone**), then
      let the monster hit you. The log must **name what absorbed it** rather than printing
      nothing. Previously an absorbed hit read as though the monster did nothing at all.
- [ ] **E. Rest menu with a full larder.** Press **Rest** underground. Should read `Page 1/3` and
      fit without pushing the map key off the panel.
- [ ] **F. Final chest + card banner.** Clear the floor/dungeon. The completion screen must list
      the **Reliquary Chest** loot, and if one dropped, the **DUNGEON CARD** banner. This is the
      one that was being built, sent, and thrown away — it has never once been confirmed.

Admin buttons exist for the awkward ones if RNG will not cooperate: **spring trap**, **drop loot**,
**flood log**.

**Not in this run** — they need extra clients, and are the only other unverified items:
`party3` for leader logout/permadeath, and a 2-client fight for party equipment rewards.

## 1. Arrow-key diagonal movement — ✅ PASSED 2026-09-10

> Owner: *"all the tests were fine and H does hunt. Rebinding seemed to work as well. Didn't seem
> laggy."* Chords land as diagonals including sloppy presses, taps are not swallowed, held travel
> is full speed, opposite keys cancel, H hunts, and 4/5 rebind West/Hunt correctly.
> **The 70ms grace window stays at 70ms** — cleared for release.

**Why it needs you:** the whole question is a 70ms timing window, which no test or screenshot can
judge. Numpad players are unaffected either way.

```bash
python tools/test_setup/run.py healthy
```

Then, on the overworld, with the **arrow keys only** (pretend the numpad does not exist):

- [ ] **Hold Up+Left together** → you move **north-west**, one step, not north-then-west.
- [ ] Try it deliberately **sloppily** — press one key clearly before the other, maybe 50ms apart.
      Still a diagonal? This is the failure mode the grace window exists for.
- [ ] **Tap a single arrow briefly** and release fast → you still take one step. A tap shorter
      than the window must not be swallowed.
- [ ] **Hold one arrow** and travel across the map → full speed, no stutter. The delay is paid
      once on the first press, never on the repeats.
- [ ] Hold **Left and Right together** → you stand still (they cancel) rather than picking one.
- [ ] **Press H** → you hunt.
- [ ] Settings → Movement Keys → press **4** → it offers to rebind **West** (not Hunt). Press
      **5** → it offers **Hunt**.

**Judgement call for you:** does the first step feel laggy? If yes, `ARROW_CHORD_GRACE_SEC` in
`client/client.gd` is the single number to lower — but lowering it makes sloppy chords misfire, so
it is a straight trade.

---

## 2. Cycle values — ✅ PASSED 2026-09-10

> Owner at the PC: faces read `cycles: 38 ward` / `cycles: 122 damage`; both Bulwarks cycled and
> paid **exactly 38** each; Venom Fang played for its stated 122 and applied its poison; the
> upgrade route works too (`Blast` showed `[cycles: 29 ward]`).
> **2e, the design question, came back qualified:** *"it will very much depend on what upgrades
> hit the players cards. If you get one with a good cycle ability you will likely want to keep it
> in."* So the pull is real but CONTINGENT on getting a good reveal — which makes deck width a
> build decision rather than a global rule. Consequence for the content pass: reveal upgrades need
> to be reachable often enough to be a build people can aim at, and there should be enough VARIETY
> that some are worth chasing for a given class. Three upgrades and five cycle types is probably
> thin for that.
> Two live findings came out of the same session — see below.

## 2 (original steps)

**Why it needs you:** whether "the card I didn't play still did something" actually makes you want
a wider deck is a question about feel.

```bash
python tools/test_setup/run.py cycle_cards
```

Loads three copies each of two dungeon cards that carry a cycle value, and a **reveal upgrade
already taken** on a class card so both routes are visible without waiting on a rank-up.

Start any fight and look at your hand:

- [ ] Cards show a **`cycles: ...`** line on the face — e.g. `cycles: 20 ward`, `cycles: N damage`.
- [ ] The class card `blast` also shows one (that is the **upgrade** route, not the card data).
- [ ] **Play one card.** The combat log names what the OTHER two paid as they cycled.
- [ ] The amount paid matches what the face promised. (Watch the shield case: an enemy hit can
      absorb some of a ward the same turn, which looks like underpayment and is not.)
- [ ] **The real question:** with these in your deck, would you now keep a sixth card rather than
      thin down to five? If not, say so — the payouts are one constant each and easy to raise.

---

## 3. Dungeon side panel — hover, chests, and the log

**Why it needs you:** hovering needs a mouse. Shipped in v0.9.763/765 but never confirmed.

```bash
python tools/test_setup/run.py in_dungeon
```

Walk onto the `D` and enter. Then:

- [ ] **Hover a theme tile in the KEY** (right panel, e.g. `v Sinking mud`) → a tooltip explains
      what it does.
- [ ] **Hover the same tile ON THE FLOOR** → the same tooltip.
- [ ] The tooltip **wraps** instead of running off the screen edge.
- [ ] **Open a small treasure chest** → the loot appears in the run log on the right, one line per
      item, and **the map stays on screen** (it used to blank).
- [ ] **Step on a trap** → the trap text appears; the floor does not vanish.
- [ ] **Clear the dungeon** → the completion screen lists the **Reliquary Chest** loot and, if one
      dropped, the **DUNGEON CARD** banner. This is the one that was being built, sent and thrown
      away.
- [ ] No **Tools** block underground, and no overworld ASCII minimap on the right.

---

## 4. Party equipment rewards  *(two clients)*

**Why it needs you:** the payout runs server-side and the sim harness cannot reach it. Reading
says it is correct; that is not the same as seeing it.

```bash
python tools/test_setup/run.py healthy
```

Fight something as a pair and win:

- [ ] **Both** members get XP.
- [ ] **Both** get their own loot — it is an independent roll each, not a split, so the two lists
      should differ.
- [ ] If **equipment** drops for one, it reaches their inventory (or auto-salvages when full).
- [ ] Both companions gain XP.

---

## 5. Leader logout / permadeath must not strand the party  *(three clients)*

**Why it needs you:** `active_parties` lives on the server, which the harness cannot instantiate.
Three exit paths were fixed; a fourth (`handle_permadeath`) was found by the check.

```bash
python tools/test_setup/run.py party3
```

- [ ] **Leader logs out to character select.** The remaining two get a **new leader** — the party
      is not left pointing at a ghost.
- [ ] The player who logged out picks another character. They are **not** still leading the party.
- [ ] Repeat with **logout of the account** — same result.

Then, for the permadeath path:

```bash
python tools/test_setup/run.py party3_leader_dies
```

- [ ] The leader dies for good → leadership **transfers**, the survivors keep a working party.

---

## 6. Rest menu with a full larder  *(quick look, low risk)*

Already screenshotted and measured (418px of content in a 610px panel), so this is a confirmation
rather than a test.

```bash
python tools/test_setup/run.py in_dungeon
```

- [ ] In a dungeon, press **Rest** with a stocked pouch → the menu reads `Page 1/3` and fits
      without pushing the key off the panel.

---

## 7. Party CONFIRM step  *(two clients, 2026-09-11, UNRELEASED)*

A party action now shows *"Lock in X? Space confirms, Q picks again"* before it is sent, because a
party submit is a one-way door (the server refuses a second action once locked in).

```bash
python tools/test_setup/run.py healthy
```

- [ ] Start a fight. Press a card's key → the log line appears and the bar reads **Confirm / Pick
      again**, with the hand still visible.
- [ ] Press the **same card key again** → it locks in (`⏳ Locked in — waiting for your party`).
- [ ] Next round: pick a card, press **Q** → back to the hand; pick a different card, press
      **Space** → that one locks in.
- [ ] Play a buff (Forcefield etc.): the **who** picker comes first, then the confirm names the
      target (*"Forcefield on test002"*).
- [ ] Solo fight on the same character: **no confirm step**, cards play immediately.

## 8. Sanctuary RECALL  *(one client, 2026-09-11, UNRELEASED)*

At character select, the Sanctuary companions page can pull a companion back from the character
holding it. No scenario yet; the setup is three clicks.

- [ ] Sanctuary → Companions: mark a registered companion for **Checkout**, pick character A, log
      in, log out to character select.
- [ ] The slot reads *(In use by A)* and the bar has **Recall**. Press it, pick the slot, Confirm
      → the slot reads *(Available)* and the log says it was recalled from A.
- [ ] Log in as A: no active companion.
- [ ] Log in as A WITH the companion, stay logged in from a second client, and try Recall from
      the first → refused with *"A is logged in right now"*.

## 9. Card instances  *(one client, 2026-09-11, UNRELEASED)*

Every copy of a card is now its own card. A save made before this splits `{card: 2}` into two
copies, each carrying the progress the card had.

Any character. Use **Admin > Items > Grant Test Cards (dungeon + companion, tradeable)**.

- [ ] Press it **twice** so you hold two Venom Fangs. The deck screen shows ×2.
- [ ] Press **−** on Venom Fang → ×1. Press **+** → back to ×2 (the benched copy returns; before,
      a thinned second copy was gone for good).
- [ ] Fight until one Venom Fang reaches a milestone and pick an upgrade. Hover the two copies
      when they come up in hand: **only one** shows the upgrade.
- [ ] At a trading post, list a Venom Fang. It sells the copy **without** the upgrade, and a
      second listing appears as its **own row** rather than merging into a stack.

## 10. Sprite Sanctuary  *(one client, 2026-09-11, UNRELEASED)*

Log in: the Sanctuary is now a sprite room on the main canvas, text on the right.

- [ ] Walk around: the camera and your sprite follow, rows sit flush, nothing flickers.
- [ ] Step onto the chest, statue, a cushion, the Stable and the door: the right panel names each
      and Space opens it. Storage / Upgrades / Stable screens still work and come back to the room.
- [ ] Log in with a fresh account: the welcome says "the little figure in the room is you".
- [ ] Look and feel: floor, walls, windows, furniture placement - what would you change?
- [ ] Companions sit on their cushions and breathe; you walk with a stride and stand when still.
- [ ] Only the things you can use have the gold ring (chest, statue, cushions, Stable, mirror, door).
- [ ] The MIRROR: click a look, go back - the room shows it; log out and in - it is kept; "Use my
      hero" puts back your last character's look.

## 11. The overworld map arrives as DATA  *(one client + a server deploy, 2026-09-11, UNRELEASED)*

The map the server sends is no longer a wall of BBCode. It is a palette plus one byte per square,
and the client rebuilds the same string: ~28 KB a step becomes ~3.4 KB. Nothing should look any
different, so this list is entirely about "did anything move".

- [ ] Walk in open wilderness: the map, the fog you have already explored, and the minimap below
      it all draw exactly as before. Nothing shifted a row.
- [ ] Stand on an NPC post and on a legacy trading post: both headers still read right and the
      map sits in the same place under them.
- [ ] Your sprite and other players' sprites sit on the correct tiles (the overlay is positioned
      off the header, so a header that grew a line would show up here first).
- [ ] Walk into a hotzone and past a dungeon, a corpse and a bounty: every coloured glyph is the
      colour it was.
- [ ] Enter and leave a dungeon: the overworld map comes back intact.
- [ ] Watch another player (the spectate path) - that one still sends the old string on purpose.
- [ ] **Old client against the new server**: keep a previous build and log in with it. It must
      still get a map. This is the one that cannot be checked any other way.

## Order I would go in

1. **Arrow movement** — highest risk, and independent of everything else.
2. **Cycle values** — the only one where a "no" changes the design rather than a number.
3. **Dungeon panel** — quick, and three separate fixes ride on it.
4. Party items last; they need the extra clients.

Items 1 and 2 are the only ones blocking a release. 3-6 are already shipped or are verification.
