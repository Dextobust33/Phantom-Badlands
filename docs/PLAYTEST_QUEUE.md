# Playtest queue — what is waiting on hands at the PC

Everything here is **committed to master and NOT released**, or released but unconfirmed. Each
item has a one-command setup and a short list of what to look at. Written 2026-09-10.

**Run one command, look at the listed things, tell me pass/fail.** If several pass, they can go
out as one release rather than several.

> Setup is always `python tools/test_setup/run.py <scenario>` from the repo root. It applies the
> save state, starts the server, and logs the clients in. `--list` shows every scenario.

---

## 1. Arrow-key diagonal movement  ⚠ highest risk

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

## 2. Cycle values — the Dune: Imperium model

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

## Order I would go in

1. **Arrow movement** — highest risk, and independent of everything else.
2. **Cycle values** — the only one where a "no" changes the design rather than a number.
3. **Dungeon panel** — quick, and three separate fixes ride on it.
4. Party items last; they need the extra clients.

Items 1 and 2 are the only ones blocking a release. 3-6 are already shipped or are verification.
