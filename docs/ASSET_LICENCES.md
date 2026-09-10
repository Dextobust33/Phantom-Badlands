# Asset licences — what may be REDISTRIBUTED, not just used

Written 2026-09-10, after buying the Raven Fantasy collection and asking the question that had
not been asked before: *"are we able to confirm if it's legal and okay for us to have those packs
there?"*

**None of this is legal advice.** It records what each licence text actually says, and which
packs are currently published in the public GitHub repo, so the call can be made on facts.

## The distinction that matters

Every pack here permits **use in the game**, including commercially. That has never been in
question, and shipping art inside `PhantomBadlandsClient.pck` is plainly that use — a `.pck` is a
packed build artefact, not a browsable asset library.

The separate question is **redistribution of the raw source files**, which is what a public git
repo does. `client/sprites/` is tracked, so every PNG in it is downloadable by anyone, forever,
including from history after a deletion.

## Status by pack

| pack | files tracked | licence | raw files in a public repo? |
|---|---|---|---|
| `raven/` (Clockwork Raven) | **0 — gitignored** | commercial use unlimited; *"cannot be distributed or sold as a separate product"* | **No — deliberately excluded** |
| `battlers/` | 4053 | LPC / OGA-BY 3.0 (see `CREDITS.md`) | Yes — permitted, share-alike avoided by selecting OGA-BY |
| `items_pack/` | 2534 | **CC0** — verified: all 1267 PNGs are byte-identical to `godot-pixel-items-source`, which ships `LICENSE CC0.txt` | Yes — fine |
| `mobs_pack/` | 732 | **CC0** — verified: all 366 PNGs byte-identical to `godot-pixel-mobs-source` | Yes — fine |
| `pet-egg-pack/` | 1298 | Hope2D Asset License v1.0 — *"the assets are not redistributed in a standalone or reusable asset form"* | **Yes — see below** |
| `darkcave/`, `tilemap_pack/` | 4 + 6 | **unidentified** — no licence file, not in `CREDITS.md` | Yes — unverified |
| `*_floor32/`, `glyph_floor32/` | derived | follow their source pack | derived works, same terms as source |

## Raven Fantasy — the terms, verbatim

From the pack pages (the zips themselves contain **no** licence text at all; all 20 "A Note to
the Dev.txt" files are byte-identical and carry only a thank-you from the artist, Caio):

> This asset can be used in any project, games, and game engines, including personal, commercial,
> and physical (print or tabletop) ones, but it cannot be distributed or sold as a separate
> product without the creator's permission (me).

and: *"Attribution is not necessary but welcome."*

So: **shipping them in the game is exactly what was bought.** Committing 190 raw PNGs to a public
repo is the part that reads as distributing the tileset — someone could clone and have the
purchased art without buying it, which is the outcome the clause exists to prevent.

Hence `client/sprites/raven/` and `client/sprites/*.zip` are in `.gitignore`.

**The cost of that, stated plainly:** a fresh clone cannot build the sprite-room work. Whoever
holds the repo must keep a private backup of the packs and drop them back at
`client/sprites/raven/`. The unzip layout is `raven/<pack_slug>/All Tileset/{16x16,32x32,48x48,64x64}.png`
plus the RPG Maker autotile sheets.

If that becomes annoying, the clean fix is to **ask Caio for written permission** to include the
files in a public repo. He is reachable and links a Patreon and Twitter in every pack note; a
"yes" in writing removes the whole problem and costs an email.

## Open: `pet-egg-pack` is the same shape, already live

Hope2D's licence permits commercial use and distribution *of finished projects*, but says the
assets must not be **"redistributed in a standalone or reusable asset form."** 1,298 raw PNGs
sitting in a public repo is arguably that, on the same reading applied to Raven Fantasy above.

This is not new and nothing has gone wrong — but it should be a deliberate decision rather than
an oversight. Three options, in increasing effort: gitignore it the way `raven/` is now; ask
Hope2D for permission; or accept the reading that a game repo is not "standalone asset form".

## Also open: two unidentified packs

`darkcave/` (the dungeon floor, wall and prop sheets this whole tile pass is built on) and
`tilemap_pack/free_tiles_16x16.png` have no licence file and no `CREDITS.md` entry. They are
small and probably free itch/OpenGameArt packs, but "probably" is not a record. Worth tracking
down and adding to `CREDITS.md` — attribution that cannot be produced is the same as none.

## Rule going forward

**Before a purchased pack is committed, its redistribution clause gets read and recorded here.**
Use rights and redistribution rights are different permissions, and every pack in this repo grants
the first. Only some grant the second.
