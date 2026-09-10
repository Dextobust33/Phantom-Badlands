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
| `pet-egg-pack/` | **0 — untracked 2026-09-10** | Hope2D v1.0 — *"not redistributed in a standalone or reusable asset form"* | **No** |
| `darkcave/` | **0 — untracked 2026-09-10** | *"You cannot redistribute this software package or its files in any form"*; commercial use and editing permitted; no AI training; credit optional | **No** |
| `tilemap_pack/` | **0 — untracked** | still unidentified — untracked until it is | **No** |
| `prop_floor32/`, `tile_floor32/`, `free_floor32/`, `egg_floor32/` | **0 — untracked** | derivatives that CARRY restricted art | **No** |
| `monster_floor32/`, `loot_floor32/`, `overworld_floor32/`, `battler_floor32/`, `glyph_floor32/` | tracked | CC0 / OGA-BY art over the flat floor COLOUR only | Yes — see "the flat-colour line" |

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

## darkcave — the terms, verbatim

From the pack page (supplied by the owner 2026-09-10):

> You can use this software package in your business and personal projects;
> You can edit and adjust packages to fit your project;
> **You cannot redistribute this software package or its files in any form or form;**
> You cannot use it for training AI
> Credit is not mandatory, but commendable;

Stricter than Raven Fantasy, which at least carves out "as a separate product". Here there is no
carve-out, and `darkcave/` is the sheet the entire dungeon tile pass is built on — floor, wall
rim, void, every scatter prop, and the landmark art.

Note the **no-AI-training** clause: it restricts using the assets to train models. It does not
restrict using an AI assistant to write code that draws them.

## Which derived bakes carry restricted art — measured, not assumed

Every dungeon sprite has the floor baked into it, so "is this bake a darkcave derivative?" is a
real question per directory. Method: each derived directory's colour palette minus the flat floor
colour, matched against each source sheet.

| derived dir | traced to | verdict |
|---|---|---|
| `prop_floor32/` | darkcave **100%** | restricted — untracked |
| `free_floor32/` | tilemap_pack **81%** | restricted — untracked |
| `tile_floor32/` | landmark art; only darkcave and free_tiles were available to bake from | untracked conservatively (18 files) |
| `egg_floor32/` | pet-egg-pack eggs | restricted — untracked |
| the rest | no source-sheet match | kept |

### The flat-colour line

The kept directories DO have darkcave's floor baked into them — but that floor tile is a **single
solid colour**, `#524B24` with zero colour spread. Measured long before this question came up: it
is why `FLOOR_COLOR` exists, why a `bgcolor` behind a glyph matches the ground exactly, and why
the occlusion compositor can key on it at all. A flat monochrome square is not the expressive
content a licence protects, and the *art* in those tiles is CC0 (`mobs_pack`, `items_pack`) or
OGA-BY (LPC battlers). That line is what kept ~2,000 files tracked instead of the whole pipeline
going dark.

## What is NOT affected — verified, so it need not be re-argued

- **The `.pck` contains no raw PNGs.** Searched the 36 MB packaged pck for literal PNG file
  headers: **zero**. Art is stored as Godot `.ctex` via `res://.godot/imported/`. The player
  download is a packed build artefact, which is the licensed use.
- **The launcher needs no change.** It queries `api.github.com/repos/<owner>/<repo>/releases`,
  which requires the repo to stay PUBLIC — and nothing here forces it private.
- **The website** (`docs/`, GitHub Pages) serves 4 gameplay screenshots — the finished work.

## Still open: git HISTORY

Untracking removes these files from the current tree, not from past commits. `git checkout` of an
old SHA still recovers them, so under "cannot redistribute in any form" the exposure is reduced,
not ended. Ending it means `git filter-repo` and a force push — see `docs/BACKLOG.md` for the
plan and its risks.
