"""Current tile vs candidate replacements, composed the way the game composes them.

Owner 2026-09-13: *"For art show me alternatives for each and I can choose the better one."*

Every option is blended onto the biome ground it really stands on and shown at the 26 pixels the
grid actually draws, beside a 5x blow-up. The number under each is its distance from the tile it
is currently confusable with - higher is better, and it is the whole reason the tile is on this
sheet.
"""
import os
from PIL import Image, ImageDraw

RAVEN = 'client/sprites/raven'
SRC = 'client/sprites/overworld32'
TILE = 32
PLAY = 26
ZOOM = 5

# tile -> (ground, the tile it collides with today, [(label, pack, row, col, span)])
JOBS = {
    'well': ('plains', 'fountain', [
        ('green_village', 6, 0, None),
        ('green_village', 2, 2, None),
        ('green_village', 7, 1, None),
    ]),
    'pylon': ('plains', None, [
        ('the_underworld', 18, 17, None),
        ('interiors', 6, 25, None),
        ('sun_city', 15, 8, None),
    ]),
    'post_marker': ('plains', 'quest_board', [
        ('green_village', 5, 14, None),
        ('green_village', 5, 3, None),
        ('green_village', 6, 3, None),
    ]),
    'healer': ('plains', 'blacksmith', [
        ('green_village', 5, 15, None),
        ('green_village', 5, 4, None),
        ('green_village', 6, 4, None),
    ]),
}


def cut(pack, row, col, span):
    sheet = Image.open(os.path.join(RAVEN, pack, 'All Tileset', '32x32.png')).convert('RGBA')
    if span is None:
        return sheet.crop((col * TILE, row * TILE, (col + 1) * TILE, (row + 1) * TILE))
    sr, sc = span
    reg = sheet.crop((col * TILE, row * TILE, (col + sc) * TILE, (row + sr) * TILE))
    return reg.resize((TILE, TILE), Image.LANCZOS)


def view(cell, ground_name):
    g = Image.open('%s/ground/%s.png' % (SRC, ground_name)).convert('RGBA').copy()
    g.alpha_composite(cell)
    return g.convert('RGB').resize((PLAY, PLAY), Image.LANCZOS)


def dist(a, b):
    pa, pb = a.load(), b.load()
    t = 0.0
    for y in range(PLAY):
        for x in range(PLAY):
            r1, g1, b1 = pa[x, y]
            r2, g2, b2 = pb[x, y]
            l1 = 0.299 * r1 + 0.587 * g1 + 0.114 * b1
            l2 = 0.299 * r2 + 0.587 * g2 + 0.114 * b2
            t += abs(l1 - l2) + 0.25 * (abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2)) / 3.0
    return t / (PLAY * PLAY)


def ink(cell):
    return sum(1 for px in cell.getdata() if px[3] > 24) / float(TILE * TILE)


def main():
    big = PLAY * ZOOM
    colw = big + 20
    W = colw * 4 + 210
    H = len(JOBS) * (big + 56) + 40
    out = Image.new('RGB', (W, H), (18, 20, 24))
    d = ImageDraw.Draw(out)
    d.text((10, 10), "Tile alternatives - each on the ground it really stands on, at the size the map draws",
           fill=(235, 235, 235))
    y = 36
    for name, (ground, rival, cands) in JOBS.items():
        cur_cell = Image.open('%s/tile/%s.png' % (SRC, name)).convert('RGBA')
        cur = view(cur_cell, ground)
        rival_view = None
        if rival:
            rival_view = view(Image.open('%s/tile/%s.png' % (SRC, rival)).convert('RGBA'), ground)

        cells = [('CURRENT', cur, cur_cell)]
        for pack, r, c, span in cands:
            cell = cut(pack, r, c, span)
            cells.append(('%s %d,%d' % (pack[:10], r, c), view(cell, ground), cell))

        for i, (label, v, cell) in enumerate(cells):
            gx = 200 + i * colw
            out.paste(v.resize((big, big), Image.NEAREST), (gx, y))
            col = (255, 130, 130) if label == 'CURRENT' else (240, 220, 140)
            d.text((gx, y + big + 3), label, fill=col)
            note = "ink %.0f%%" % (ink(cell) * 100)
            if rival_view is not None:
                note += "   vs %s: %.1f" % (rival[:9], dist(v, rival_view))
            bad = ink(cell) < 0.08 or (rival_view is not None and dist(v, rival_view) < 18.0)
            d.text((gx, y + big + 17), note, fill=(220, 110, 110) if bad else (150, 190, 150))
        d.text((10, y + big // 2 - 20), "tile:%s" % name, fill=(255, 210, 120))
        if rival:
            d.text((10, y + big // 2 - 4), "today reads as", fill=(150, 150, 150))
            d.text((10, y + big // 2 + 10), "'%s'" % rival, fill=(255, 130, 130))
        else:
            d.text((10, y + big // 2 - 4), "today draws", fill=(150, 150, 150))
            d.text((10, y + big // 2 + 10), "NOTHING", fill=(255, 130, 130))
        y += big + 56
    path = 'claude_screenshots/tile_alternatives.png'
    out.save(path)
    print("wrote %s (%dx%d)" % (path, W, H))


if __name__ == '__main__':
    main()
