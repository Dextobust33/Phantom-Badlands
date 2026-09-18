"""Render explicit (pack, row, col, span) regions side by side, at play size and blown up.

Owner 2026-09-13: *"For art show me alternatives for each and I can choose the better one."*
Owner 2026-09-18: *"The center tile shows a big 3x3 blue thing for some reason when I'm near it
then goes to the half sword sprite once I walk away from it."*

⛑ BOTH HALVES, ALWAYS. A multi-cell tile bakes TWO images - the full-size one PASS 2 draws and
the shrunk single cell the minimap and the fallback use - and the owner has now been shown a
pick that looked fine at full size and terrible shrunk. Each candidate here renders both.

USAGE
    python tools/tile_region_sheet.py post_marker
"""
import os
import sys

from PIL import Image, ImageDraw

RAVEN = 'client/sprites/raven'
TILE = 32
PLAY = 26
ZOOM = 4
OUT = 'claude_screenshots'

# job -> (ground, [(label, pack, row, col, (rows, cols))])
JOBS = {
    # The tile at the CENTRE of all 120 posts, so among the most-seen art in the game.
    # Owner 2026-09-18: *"The center tile shows a big 3x3 blue thing for some reason when I'm near
    # it then goes to the half sword sprite once I walk away from it. Neither of these are good."*
    # The 3x3 blue thing is a hanging WALL BANNER; the small one is that banner squashed into a
    # single cell, which is where the stripes come from.
    'post_marker': ('post', [
        ('CURRENT sun_city 23,16 - wall banner', 'sun_city', 23, 16, (3, 3)),
        ('A: stone fountain + statue', 'sun_city', 22, 1, (3, 3)),
        ('B: blue fountain, lion spout', 'sun_city', 22, 4, (3, 3)),
        ('C: blue fountain, wide basin', 'sun_city', 22, 7, (3, 3)),
    ]),
    'enchant_table': ('post', [
        ('OLD craft_stations 7,1 - right half only', 'craft_stations', 7, 1, (2, 1)),
        ('NEW craft_stations 7,0 - the whole desk', 'craft_stations', 7, 0, (2, 2)),
    ]),
}


def sheet_path(pack):
    return os.path.join(RAVEN, pack, 'All Tileset', '32x32.png')


def region(pack, row, col, span):
    sheet = Image.open(sheet_path(pack)).convert('RGBA')
    sr, sc = span
    return sheet.crop((col * TILE, row * TILE, (col + sc) * TILE, (row + sr) * TILE))


def ground_img(name):
    p = os.path.join('client/sprites/overworld32/ground', name + '.png')
    return Image.open(p).convert('RGBA')


def main():
    job = sys.argv[1]
    gname, cands = JOBS[job]
    g = ground_img(gname)
    pad = 24
    cw = 4 * TILE * ZOOM + pad
    sheet = Image.new('RGB', (cw * len(cands) + pad, 4 * TILE * ZOOM + 140), (24, 20, 28))
    d = ImageDraw.Draw(sheet)
    for i, (label, pack, row, col, span) in enumerate(cands):
        x0 = pad + i * cw
        art = region(pack, row, col, span)
        sr, sc = span
        # (a) full size, on ground, the way PASS 2 draws it
        bg = Image.new('RGBA', (sc * TILE, sr * TILE), (0, 0, 0, 0))
        for yy in range(sr):
            for xx in range(sc):
                bg.alpha_composite(g, (xx * TILE, yy * TILE))
        bg.alpha_composite(art)
        big = bg.convert('RGB').resize((sc * TILE * ZOOM, sr * TILE * ZOOM), Image.NEAREST)
        d.text((x0, 8), label, fill=(255, 210, 120))
        d.text((x0, 26), 'full size (PASS 2)', fill=(150, 150, 160))
        sheet.paste(big, (x0, 44))
        # (b) the SHRUNK single cell - minimap and fallback
        one = art.resize((TILE, TILE), Image.LANCZOS)
        cell = g.copy()
        cell.alpha_composite(one)
        small = cell.convert('RGB').resize((PLAY, PLAY), Image.LANCZOS)
        y1 = 44 + sr * TILE * ZOOM + 16
        d.text((x0, y1), 'shrunk to 1 cell, at play size:', fill=(150, 150, 160))
        sheet.paste(small.resize((PLAY * 4, PLAY * 4), Image.NEAREST), (x0, y1 + 18))
    os.makedirs(OUT, exist_ok=True)
    p = os.path.join(OUT, 'pick_%s.png' % job)
    sheet.save(p)
    print(p)


if __name__ == '__main__':
    main()
