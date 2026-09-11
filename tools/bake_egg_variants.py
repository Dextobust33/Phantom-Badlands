"""Match every cosmetic VARIANT to its own egg sprite, and write EggSprites.SPRITE_BY_VARIANT.

WHY THIS EXISTS. The table in `client/egg_sprites.gd` says "GENERATED, not hand-written ...
re-run the generator described above" — and that generator was never committed. Third time this
session (the landmark tiles and the glyph tiles had the same hole), so it is a script now.

WHAT CHANGED, 2026-09-11. The original matcher was greedy nearest-colour with a "spread the picks
out" penalty, tuned to 2000. Measured at the time: 95 distinct eggs, 24 variants sharing one with
a near-identical-coloured neighbour. The owner accepted that. It later showed up as 20 warnings
from `verify_dungeon_art.gd` — Zebra and Duality drawing the same egg, Framed / Misty / Corona all
drawing another — so a player cannot tell those variants apart before hatching, which is the one
thing this table exists to make possible.

A penalty cannot guarantee uniqueness; it only discourages collisions. With 119 variants and 648
eggs, a one-to-one assignment plainly exists, so this solves it as an ASSIGNMENT instead:
repeatedly take the globally cheapest (variant, egg) pair still available. That is greedy over
the whole matrix rather than per-variant, which is what makes it collision-free by construction —
uniqueness stops being a thing to tune and becomes a thing the algorithm cannot violate.

TWO MEASUREMENT NOTES carried over from the original, both mistakes that were caught before they
shipped and would be easy to reintroduce:
  * Near-black pixels are discarded as OUTLINE only when they are a MINORITY. Discarding them
    unconditionally means a black egg can never match a black variant, which sent Obsidian,
    Eclipse, Void, Barcode and Jailbird to pale eggs.
  * Filenames are NOT trusted. They carry colour WORDS ("red-blue"), and a red-blue egg is a
    blended purple — the name describes the inputs, not what the player sees. Only pixels count.

PATTERN is still lost: striped / split_v / checker cannot survive being a single sprite. That was
accepted by the owner and is unchanged here.

USAGE — two steps, because the variant list lives in GDScript and the pixels need PIL:
    godot --headless --path . --script res://tools/dump_egg_variants.gd
    python tools/bake_egg_variants.py            # rewrites the table in client/egg_sprites.gd
    python tools/bake_egg_variants.py --dry-run  # report only

`tools/egg_variants.json` is DERIVED. Re-dump it whenever EGG_VARIANTS changes — a stale dump
would silently match the old variant list against the current art.
"""
import glob
import json
import os
import re
import sys

from PIL import Image

EGG_DIR = 'client/sprites/pet-egg-pack/eggs'
VARIANTS_JSON = 'tools/egg_variants.json'
TARGET = 'client/egg_sprites.gd'

BLACK_CUTOFF = 60          # a pixel this dark on every channel is a candidate outline
ALPHA_CUTOFF = 40


def dominant_colour(path):
    """The egg's body colour, as the player sees it.

    Averages opaque pixels. Near-black is dropped ONLY if it is a minority — otherwise a black
    egg would measure as whatever few light pixels it has.
    """
    im = Image.open(path).convert('RGBA')
    px = list(im.getdata())
    opaque = [p for p in px if p[3] > ALPHA_CUTOFF]
    if not opaque:
        return None
    def is_dark(p):
        return p[0] < BLACK_CUTOFF and p[1] < BLACK_CUTOFF and p[2] < BLACK_CUTOFF

    dark_count = sum(1 for p in opaque if is_dark(p))
    # Majority-dark egg: keep everything, or a black egg measures as its few light pixels.
    if dark_count > len(opaque) / 2:
        body = opaque
    else:
        body = [p for p in opaque if not is_dark(p)] or opaque
    n = len(body)
    return (sum(p[0] for p in body) / n, sum(p[1] for p in body) / n, sum(p[2] for p in body) / n)


def distinct_colours(path):
    """How many distinct opaque colours the sprite has. Mirrors verify_dungeon_art.gd's own
    test (alpha >= 0.8, count unique RGBA) so the generator and the gate cannot disagree."""
    im = Image.open(path).convert('RGBA')
    seen = set()
    for p in im.get_flattened_data() if hasattr(im, 'get_flattened_data') else list(im.getdata()):
        if p[3] < 204:      # 0.8 * 255
            continue
        seen.add(p)
        if len(seen) >= 20:
            return 20
    return len(seen)


def hex_to_rgb(h):
    h = h.strip().lstrip('#')
    if len(h) != 6:
        return None
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def variant_colour(v):
    """A variant's representative colour: its own, blended with color2 when it has one."""
    c1 = hex_to_rgb(v.get('color', ''))
    if c1 is None:
        return None
    c2 = hex_to_rgb(v.get('color2', '') or '')
    if c2 is None:
        return c1
    return tuple((a + b) / 2.0 for a, b in zip(c1, c2))


def dist2(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b))


def main():
    dry = '--dry-run' in sys.argv
    variants = json.load(open(VARIANTS_JSON, encoding='utf-8'))
    eggs = sorted(glob.glob(os.path.join(EGG_DIR, '**', '*.png'), recursive=True))
    if not eggs:
        raise SystemExit('no egg art on disk — restore the licensed pack first '
                         '(see tools/licensed_assets.manifest)')
    print('%d variants, %d egg sprites' % (len(variants), len(eggs)))
    if len(eggs) < len(variants):
        raise SystemExit('fewer eggs than variants — a unique assignment is impossible')

    egg_rgb = {}
    skipped_flat = 0
    for e in eggs:
        # Skip untextured TEMPLATES. `verify_dungeon_art.gd` fails the build on any egg with
        # fewer than 20 distinct opaque colours ("an untextured template"), and the pack ships
        # several — 0624-egg-base.png among them. Found the hard way: the first clean run of
        # this matcher handed that base to Ivory and the gate rejected it. Matching the gate's
        # own threshold here means the generator cannot produce art the build will refuse.
        if distinct_colours(e) < 20:
            skipped_flat += 1
            continue
        c = dominant_colour(e)
        if c is not None:
            egg_rgb[e] = c
    print('measured %d eggs (%d flat templates skipped)' % (len(egg_rgb), skipped_flat))
    if len(egg_rgb) < len(variants):
        raise SystemExit('only %d usable eggs for %d variants' % (len(egg_rgb), len(variants)))

    # Build every (cost, variant, egg) and consume globally cheapest-first. Greedy over the whole
    # matrix, not per-variant: that is what makes collisions impossible rather than merely
    # discouraged.
    pairs = []
    for v in variants:
        vc = variant_colour(v)
        if vc is None:
            continue
        for e, ec in egg_rgb.items():
            pairs.append((dist2(vc, ec), v['name'], e))
    pairs.sort(key=lambda t: t[0])

    taken_v, taken_e, assign = set(), set(), {}
    for cost, vname, e in pairs:
        if vname in taken_v or e in taken_e:
            continue
        taken_v.add(vname)
        taken_e.add(e)
        assign[vname] = (e, cost)
        if len(assign) == len(variants):
            break

    missing = [v['name'] for v in variants if v['name'] not in assign]
    if missing:
        raise SystemExit('unassigned variants: %s' % missing)
    assert len(set(e for e, _ in assign.values())) == len(assign), 'collision survived'

    worst = sorted(assign.items(), key=lambda kv: -kv[1][1])[:5]
    print('\nevery variant has its OWN egg: %d distinct sprites, 0 collisions' % len(assign))
    print('worst colour matches (these are the recolour candidates):')
    for name, (e, cost) in worst:
        print('   %-14s dist %6.0f  %s' % (name, cost ** 0.5, os.path.basename(e)))

    if dry:
        print('\n--dry-run: nothing written')
        return

    rows = []
    for v in variants:
        e = assign[v['name']][0].replace('\\', '/')
        rows.append('\t"%s": "res://%s",' % (v['name'], e))
    body = 'const SPRITE_BY_VARIANT := {\n' + '\n'.join(rows) + '\n}'

    src = open(TARGET, encoding='utf-8', newline='').read()
    nl = '\r\n' if '\r\n' in src else '\n'
    flat = src.replace('\r\n', '\n')
    m = re.search(r'const SPRITE_BY_VARIANT := \{.*?\n\}', flat, re.S)
    if not m:
        raise SystemExit('could not find SPRITE_BY_VARIANT in %s' % TARGET)
    flat = flat[:m.start()] + body + flat[m.end():]
    open(TARGET, 'w', encoding='utf-8', newline='').write(flat.replace('\n', nl))
    print('\nwrote %d rows to %s' % (len(rows), TARGET))


if __name__ == '__main__':
    main()
