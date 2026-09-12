"""Render a Raven tileset as a LABELLED grid, so cells can be picked by eye and then by number.

Phase 2.95 PHASE 2 needs real art for 67 overworld tile types across 6 biomes. The packs are
large sheets (`All Tileset/32x32.png`, up to 40x53 cells), and picking a cell means looking at it.
`tools/bake_sanctuary.py` went through the same exercise for 16 pieces, and the note it left -
that finding the one seamless floor cell took measuring rather than guessing - is why this exists
as a tool rather than as a one-off.

USAGE
    python tools/tileset_contact_sheet.py green_forest_v2
    python tools/tileset_contact_sheet.py green_forest_v2 --rows 0-8     # a slice, bigger
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

RAVEN = 'client/sprites/raven'
OUT = 'claude_screenshots'
CELL = 32
SCALE = 3
LABEL = 13


def find_sheet(pack):
    for name in ('32x32.png', '32X32.png', 'Tileset.png'):
        p = os.path.join(RAVEN, pack, 'All Tileset', name)
        if os.path.exists(p):
            return p
    raise SystemExit('no All Tileset sheet for %r' % pack)


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    pack = sys.argv[1]
    row_lo, row_hi = 0, 10 ** 9
    if '--rows' in sys.argv:
        lo, hi = sys.argv[sys.argv.index('--rows') + 1].split('-')
        row_lo, row_hi = int(lo), int(hi)

    sheet = Image.open(find_sheet(pack)).convert('RGBA')
    cols = sheet.size[0] // CELL
    rows = sheet.size[1] // CELL
    row_hi = min(row_hi, rows - 1)
    n_rows = row_hi - row_lo + 1

    step = CELL * SCALE + LABEL
    w = LABEL + cols * step
    h = LABEL + n_rows * step
    out = Image.new('RGBA', (w, h), (24, 24, 28, 255))
    d = ImageDraw.Draw(out)
    try:
        font = ImageFont.truetype(r'C:\Windows\Fonts\consola.ttf', 11)
    except OSError:
        font = ImageFont.load_default()

    for c in range(cols):
        d.text((LABEL + c * step + 2, 1), str(c), font=font, fill=(200, 200, 120, 255))
    for i in range(n_rows):
        r = row_lo + i
        d.text((1, LABEL + i * step + CELL * SCALE // 2), str(r), font=font, fill=(200, 200, 120, 255))
        for c in range(cols):
            cell = sheet.crop((c * CELL, r * CELL, (c + 1) * CELL, (r + 1) * CELL))
            cell = cell.resize((CELL * SCALE, CELL * SCALE), Image.NEAREST)
            x = LABEL + c * step
            y = LABEL + i * step
            # a checker behind, so transparent cells are obviously transparent
            for by in range(0, CELL * SCALE, 8):
                for bx in range(0, CELL * SCALE, 8):
                    shade = 60 if ((bx // 8 + by // 8) % 2) else 45
                    d.rectangle([x + bx, y + by, x + bx + 7, y + by + 7], fill=(shade, shade, shade, 255))
            out.alpha_composite(cell, (x, y))
            d.rectangle([x - 1, y - 1, x + CELL * SCALE, y + CELL * SCALE], outline=(90, 90, 100, 255))

    os.makedirs(OUT, exist_ok=True)
    dest = os.path.join(OUT, 'tileset_%s_%d-%d.png' % (pack, row_lo, row_hi))
    out.save(dest)
    print('%s: %d x %d cells -> %s (%dx%d)' % (pack, cols, rows, dest, w, h))


if __name__ == '__main__':
    main()
