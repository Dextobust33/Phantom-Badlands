"""Show the cells of a Raven pack that could actually serve as an overworld tile.

Owner 2026-09-13: *"For art show me alternatives for each and I can choose the better one."*

Picking a replacement cell used to mean staring at a 35x21 sheet. Most of those cells can be
ruled out mechanically - too empty to see at 26px, or so close to a tile already in use that the
two would be confusable - which is exactly the fault this whole audit was opened to find. What
survives is a short labelled grid worth looking at.

USAGE
    python tools/tile_candidates.py interiors --rows 6-14
    python tools/tile_candidates.py green_village --avoid fountain
"""
import os
import sys

from PIL import Image, ImageDraw

RAVEN = 'client/sprites/raven'
TILE = 32
PLAY_PX = 26
MIN_INK = 0.14        # a little above the baker's floor: a CANDIDATE should be clearly visible
OUT = 'claude_screenshots'


def sheet_path(pack):
    return os.path.join(RAVEN, pack, 'All Tileset', '32x32.png')


def play_view(cell, ground):
    base = ground.copy()
    base.alpha_composite(cell)
    return base.convert('RGB').resize((PLAY_PX, PLAY_PX), Image.LANCZOS)


def dist(a, b):
    pa, pb = a.load(), b.load()
    t = 0.0
    for y in range(PLAY_PX):
        for x in range(PLAY_PX):
            r1, g1, b1 = pa[x, y]
            r2, g2, b2 = pb[x, y]
            l1 = 0.299 * r1 + 0.587 * g1 + 0.114 * b1
            l2 = 0.299 * r2 + 0.587 * g2 + 0.114 * b2
            t += abs(l1 - l2) + 0.25 * (abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2)) / 3.0
    return t / (PLAY_PX * PLAY_PX)


def main():
    pack = sys.argv[1]
    row_lo, row_hi = 0, 10 ** 9
    avoid = []
    if '--rows' in sys.argv:
        a, b = sys.argv[sys.argv.index('--rows') + 1].split('-')
        row_lo, row_hi = int(a), int(b)
    if '--avoid' in sys.argv:
        avoid = sys.argv[sys.argv.index('--avoid') + 1].split(',')

    sheet = Image.open(sheet_path(pack)).convert('RGBA')
    cols, rows = sheet.size[0] // TILE, sheet.size[1] // TILE
    ground = Image.open('client/sprites/overworld32/ground/plains.png').convert('RGBA')

    # Every tile already in use, so a candidate that duplicates one can be dropped before it is
    # ever looked at - the whole point of the audit that produced this tool.
    existing = {}
    tdir = 'client/sprites/overworld32/tile'
    for f in sorted(os.listdir(tdir)):
        if f.endswith('.png'):
            existing[f[:-4]] = play_view(
                Image.open(os.path.join(tdir, f)).convert('RGBA'), ground)

    keep = []
    for r in range(max(0, row_lo), min(rows, row_hi + 1)):
        for c in range(cols):
            cell = sheet.crop((c * TILE, r * TILE, (c + 1) * TILE, (r + 1) * TILE))
            ink = sum(1 for px in cell.getdata() if px[3] > 24) / float(TILE * TILE)
            if ink < MIN_INK:
                continue
            view = play_view(cell, ground)
            nearest, nd = None, 1e9
            for name, ex in existing.items():
                d = dist(view, ex)
                if d < nd:
                    nd, nearest = d, name
            if nd < 12.0:
                continue        # already have this tile under another name
            if avoid and nearest in avoid and nd < 25.0:
                continue
            keep.append((r, c, cell, view, nearest, nd))

    print("%s: %d of %d cells are visible AND not a duplicate of a tile already in use"
          % (pack, len(keep), cols * (min(rows, row_hi + 1) - max(0, row_lo))))

    if not keep:
        return
    per_row = 12
    zoom = PLAY_PX * 4
    W = per_row * (zoom + 8) + 12
    H = ((len(keep) + per_row - 1) // per_row) * (zoom + 26) + 34
    out = Image.new('RGB', (W, H), (18, 20, 24))
    d = ImageDraw.Draw(out)
    d.text((10, 10), "%s - usable cells, shown on plains at 4x. Label is (row, col)." % pack,
           fill=(235, 235, 235))
    for i, (r, c, cell, view, nearest, nd) in enumerate(keep):
        gx = (i % per_row) * (zoom + 8) + 8
        gy = (i // per_row) * (zoom + 26) + 32
        out.paste(view.resize((zoom, zoom), Image.NEAREST), (gx, gy))
        d.text((gx, gy + zoom + 2), "%d,%d" % (r, c), fill=(240, 220, 140))
    path = os.path.join(OUT, 'candidates_%s.png' % pack)
    out.save(path)
    print("wrote %s (%dx%d)" % (path, W, H))


if __name__ == '__main__':
    main()
