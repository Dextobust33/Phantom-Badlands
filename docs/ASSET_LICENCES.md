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

## The private backup — how to keep this art safe and restorable

The restricted art is no longer in git, so **git is no longer your backup**. Losing the working
copy means re-downloading (or re-buying) the packs and re-running the bakes. Set this up once.

### DONE 2026-09-10: the private repo exists

**<https://github.com/Dextobust33/Phantom-Badlands-Art>** - private, 1,849 files, holding every
path in `tools/licensed_assets.manifest` plus `purchased-originals/` (the 20 untouched Raven
`.zip` files as bought, so that pack can always be restored from source rather than from a copy).

Its `LICENSING.md` carries the per-pack terms verbatim and opens with "DO NOT MAKE THIS
REPOSITORY PUBLIC", so the restriction travels with the art instead of living in someone's memory.

**Verified, not assumed:**

- all 1,827 art files compared by MD5 against the working tree - **0 missing, 0 differing**
- a restore DRILL: `prop_floor32` was deleted outright, the gate went red and named it, the
  directory was restored from the art repo by the documented command, the gate went green, and the
  occlusion probe passed. The backup is known to be restorable, not merely known to exist.

To restore on a fresh machine:

```bash
git clone https://github.com/Dextobust33/Phantom-Badlands-Art.git pb-art
cp -r pb-art/client/sprites/* <phantasia-revival>/client/sprites/
cd <phantasia-revival> && bash tools/check_licensed_assets.sh    # must print ok
```

### The risks that were accepted going in

Stated plainly so nobody has to rediscover them:

1. **A private repo is one click from public.** That is the standing hazard an offline copy does
   not have. Mitigated by `LICENSING.md`, a blunt repo description, and no collaborators.
2. **It puts the files in plaintext on a third party.** Private storage is not redistribution -
   the same category as Dropbox - but it is transmission, and a strict reading of "in any form"
   could argue. An encrypted archive was the alternative; the convenience of a repo was chosen.
3. **The bakes still cannot be regenerated.** See below - this backup mitigates that, it does not
   fix it.

### The local snapshot that already exists

Taken automatically before the history rewrite on 2026-09-10:

```
C:\Users\Dexto\Documents\phantom-badlands-backup\<timestamp>\
    licensed-art\client\sprites\...      28 MB — every restricted directory, plus the Raven zips
    phantom-badlands-mirror.git          147 MB — the FULL pre-rewrite history
```

Keep the mirror until you are satisfied the rewrite went well; it is the only copy of the old
SHAs. After that it can go, and the `licensed-art` folder is the one worth keeping forever.

### What stops this being silently forgotten

`tools/licensed_assets.manifest` lists every restricted directory and its expected file count.
`tools/check_licensed_assets.sh` verifies them and is wired into `tools/verify_release_build.sh`,
so **a release cannot be built without the art present**. Without that check, a fresh clone
produces a dungeon of letters and blank tiles that looks like a rendering bug rather than a
missing checkout — proven by hiding `prop_floor32` and watching the gate go red.

When a new restricted pack is added: drop it in, add a line to the manifest, run
`bash tools/check_licensed_assets.sh --update`, gitignore the path, and record the terms above.
### Draft: GitHub Support request (still needs sending)

The history rewrite removed the files from every reachable commit, but GitHub keeps unreachable
objects until it garbage-collects, and it will still serve them **by direct SHA**. Verified on
2026-09-10: an old commit that contained `pet-egg-pack/LICENSE.txt` still returned HTTP 200 from
both `raw.githubusercontent.com` and the contents API after the force push.

Only GitHub Support can force the GC. Send this at <https://support.github.com/request>:

> **Subject:** Request garbage collection after history rewrite — Dextobust33/Phantom-Badlands
>
> I rewrote the history of `Dextobust33/Phantom-Badlands` with `git filter-repo` to remove
> licensed third-party art that I am permitted to use in my game but not to redistribute, and
> force-pushed all branches and tags.
>
> The objects are unreachable from any ref, but they are still served by direct commit SHA — for
> example `https://raw.githubusercontent.com/Dextobust33/Phantom-Badlands/<SHA>/client/sprites/pet-egg-pack/LICENSE.txt`
> still returns 200.
>
> Please run garbage collection on the repository so the unreachable objects are no longer
> retrievable. There are no forks I need preserved.

Note what this cannot fix: anyone who already cloned or forked keeps the data, and old SHAs would
have to be known to fetch them. The exposure after GC is essentially zero for a passer-by.

### Re-checking whether the GC has run

Request submitted 2026-09-10. Do not guess whether it happened - run:

```bash
bash tools/check_github_gc.sh
```

It refetches the three sample SHAs and reports the repo size GitHub advertises. Exit 0 means the
objects are gone. At submission time all three still returned HTTP 200 and the size was unchanged
at 120,127 KB, which is the signal that unreachable objects are still retained.

Established while filing, and worth keeping: the repository has **0 forks** and has **never had a
pull request** (no `refs/pull/*` refs). Those are the two things that normally keep rewritten
commits alive, and neither applies here.

## ⚠ The 134 files that cannot be regenerated

`prop_floor32` (11), `tile_floor32` (18), `free_floor32` (5) and `egg_floor32` (100) are baked
derivatives, and **the scripts that produced them do not exist** - not in the repo, not anywhere
in its history. Checked, not assumed: no commit ever added a baker. They were ad-hoc and are gone.

So those 134 PNGs live in exactly three places: the working tree, the local snapshot, and the
private art repo. Lose all three and they must be re-derived by rewriting the bakers from scratch
against `client/dungeon_tiles.gd`.

**The real fix is to write the bake generators as committed tools.** They are OUR code operating
on assets we own, not licensed art, so they belong in the PUBLIC repo. That turns 134
irreplaceable files into reproducible output and means a fresh clone plus the source packs can
rebuild everything. On the backlog; until it lands, the backup above is the mitigation.


## The rewrite was not finished when I first said it was

Recorded because the mistake is more instructive than the fix.

After `git filter-repo` and the force push, the check run was: *is any restricted path reachable
in this repository?* It came back clean, and that was reported as done. **It asked the wrong
repository.** Three release tags — `v0.9.764`, `v0.9.765`, `v0.9.766` — and a branch,
`release/v0.9.747`, existed ONLY on the remote. They were created server-side by
`gh release create`, so the local clone never had them, and `git push --force --tags` pushes LOCAL
tags. All four still pointed into the old history.

That is not "unreachable objects awaiting GC". Those refs were **live**, and every restricted file
was browsable through them — `raw.githubusercontent.com/.../v0.9.766/client/sprites/darkcave/...`
returned 200. A garbage collection would never have touched them, because they were referenced.
The support request would have been answered, closed, and the art would still have been public.

It surfaced only because a completely unrelated question — "what is unreleased?" — ran
`git log v0.9.766..HEAD` and got *nothing*, because the tag was not in local history at all.

Fixed by mapping each stale SHA through `.git/filter-repo/commit-map` (which had all four, since
the commits *were* local at rewrite time — only the tags were not) and force-pushing the corrected
refs. All 800 remote refs now audit clean, and every GitHub Release kept its 7 assets.

**`tools/check_no_restricted_refs.sh` is the lesson made executable:** it walks the REMOTE ref
list, not the local one, and fails on any ref it cannot account for.

### And a second wrong instrument, found the same way

`raw.githubusercontent.com` is fronted by a CDN with `max-age=300` that caches by path and ignores
cache-busting query strings. After the refs were corrected it kept serving the deleted files with
`X-Cache: HIT`, which read exactly like "the fix did not work". The authority is the **contents
API** (`/repos/:owner/:repo/contents/PATH?ref=REF`), which answered 404 immediately.
`tools/check_github_gc.sh` was rewritten to use it.

The GC request itself still stands: the three sample dangling SHAs are genuinely unreachable now
and are still served by SHA through the API, which is the retention the request is about.
