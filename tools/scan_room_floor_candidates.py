"""Find NEW room-floor candidates in the Raven packs that are not yet in the pool.

The pool is seven packs and six of them bake a single tile, so "each room picks its own look"
currently means seven looks for a whole dungeon. Owner, 2026-09-10: *"If we need more variety we
can still look at the other sprite packs we have for more Floors, walls, and decor."*

Twenty packs are unzipped; seven are in the pool and `interiors` was rejected for a recorded
reason, which leaves twelve to look at.

WHY A SCANNER AND NOT AN EYE. `bake_room_floors.py` records how the original seven were chosen and
why it is not by eye: picking a sheet cell by eye has already covered a room in black notches once.
It also records the trap - the top-scoring cell for `beach_ocean_and_shore` and `miners_cave` is
WATER, and for `shroom_chasm` a boulder. So this does the measurable part and then RENDERS the
survivors for the part no measurement does.

THE GATES ARE IMPORTED, NOT RESTATED. `verify()` in the bake script is what will run at bake time;
a second copy of those thresholds here would be the "one value, two places" shape this repo keeps
getting bitten by, and it would let the shortlist drift from what actually bakes.

USAGE
    python tools/scan_room_floor_candidates.py            # shortlist + contact sheet
"""
import colorsys
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bake_room_floors as B   # noqa: E402  - the gates and the sheet locator, not a copy of them

CELL = 16
OUT_SHEET = 'claude_screenshots/room_floor_candidates.png'
## Flat ground has a low colour spread; an OBJECT (a boulder, a chest, a pool of water with a
## highlight) has a high one. This is a shortlist filter, never a ranking - see the bake script's
## note that contrast is "a GATE, never the thing maximised".
MAX_SPREAD = 26.0
TOP_PER_PACK = 4


def spread(img):
    """Mean per-channel standard deviation - how BUSY a cell is."""
    px = [p[:3] for p in img.convert('RGBA').getdata() if p[3] == 255]
    if not px:
        return 999.0
    out = 0.0
    for i in range(3):
        vals = [p[i] for p in px]
        m = sum(vals) / len(vals)
        out += (sum((v - m) ** 2 for v in vals) / len(vals)) ** 0.5
    return out / 3.0


def passes_gates(tile, corr, rock):
    """The SAME two gates `verify()` enforces at bake time, evaluated without raising."""
    got = B._mean_hsv(tile)
    if got is None:
        return False, 'not opaque'
    (h, _s, v), _m = got
    wall_dh = min(abs(h - rock[0]), 1 - abs(h - rock[0]))
    if abs(v - rock[2]) < B.MIN_WALL_VALUE_GAP and wall_dh < B.MIN_WALL_HUE_GAP:
        return False, 'wall gate'
    dh = min(abs(h - corr[0]), 1 - abs(h - corr[0]))
    dv = abs(v - corr[2])
    if dh < B.MIN_CORR_HUE_GAP and dv < B.MIN_CORR_VALUE_GAP:
        return False, 'corridor gate'
    return True, ''


def main():
    corr, _ = B._reference('SHEET_CAVE16', 'CAVE_FLOOR', 16)
    rock, _ = B._reference('SHEET_CAVE32', 'CAVE_ROCK', 32, require_opaque=False)
    in_pool = set(B.FLOORS)
    packs = sorted(d for d in os.listdir(B.RAVEN)
                   if os.path.isdir(os.path.join(B.RAVEN, d)))
    rows = []
    print('pool already has: %s' % ', '.join(sorted(in_pool)))
    print('%-26s %6s %8s %s' % ('pack', 'cells', 'passed', 'best candidates (col,row) spread'))
    for pack in packs:
        if pack in in_pool or pack in ('corner', 'interiors'):
            continue
        try:
            sheet_path = B.sheet_for(pack)
        except SystemExit:
            print('%-26s %6s %8s %s' % (pack, '-', '-', 'no tileset found'))
            continue
        im = Image.open(sheet_path).convert('RGBA')
        across, down = im.size[0] // CELL, im.size[1] // CELL
        cands = []
        total = 0
        for cy in range(down):
            for cx in range(across):
                tile = im.crop((cx * CELL, cy * CELL, (cx + 1) * CELL, (cy + 1) * CELL))
                if B._mean_hsv(tile) is None:
                    continue
                total += 1
                ok, _why = passes_gates(tile, corr, rock)
                if not ok:
                    continue
                sp = spread(tile)
                if sp > MAX_SPREAD:
                    continue
                cands.append((sp, cx, cy, tile))
        cands.sort(key=lambda t: t[0])
        keep = cands[:TOP_PER_PACK]
        print('%-26s %6d %8d %s' % (pack, total, len(cands),
              ' '.join('(%d,%d) %.0f' % (c[1], c[2], c[0]) for c in keep) or '-'))
        for sp, cx, cy, tile in keep:
            rows.append((pack, cx, cy, sp, tile))

    if not rows:
        print('\nno candidates survived the gates')
        return
    # The contact sheet: every survivor beside the wall rim and the corridor floor, which is the
    # comparison the gates are about. Scaled 3x because these decisions are made by looking.
    rim = B._reference_image('SHEET_CAVE32', 'CAVE_ROCK', 32).resize((CELL, CELL), Image.NEAREST)
    cor = B._reference_image('SHEET_CAVE16', 'CAVE_FLOOR', 16)
    pad, scale = 4, 3
    w = (CELL * 3 + pad * 4) * scale
    h = (CELL + pad * 2) * scale * len(rows)
    out = Image.new('RGBA', (w, h), (18, 18, 22, 255))
    for i, (pack, cx, cy, sp, tile) in enumerate(rows):
        y = (CELL + pad * 2) * scale * i + pad * scale
        for j, img in enumerate((tile, rim, cor)):
            x = (pad + (CELL + pad) * j) * scale
            out.paste(img.resize((CELL * scale, CELL * scale), Image.NEAREST), (x, y))
    os.makedirs(os.path.dirname(OUT_SHEET), exist_ok=True)
    out.save(OUT_SHEET)
    print('\nwrote %s - %d candidates, each beside the wall rim and the corridor floor'
          % (OUT_SHEET, len(rows)))
    print('LOOK AT IT before adding anything: the measurable gates cannot tell ground from water.')


if __name__ == '__main__':
    main()
