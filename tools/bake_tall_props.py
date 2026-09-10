"""Bake the TWO-CELL props as separate top and bottom halves.

These were dropped from the scatter pool on 2026-09-10 and the reason is recorded in
dungeon_tiles.gd: the cave sheet's lamps occupy (19,5)+(19,6) and the dead shrub (17,3)+(17,4),
so baking one cell yields half an object. Owner, seeing them in play: *"the two lanterns you added
in those are actually two vertical squares tall... currently they render as half of a lamppost."*

A 2-cell object cannot be squeezed into one grid cell - squashing it halves its scale against
everything around it - so it needs the object to span two cells. That is the ROW SPLIT, and it is
also what multi-tile decor needs, which is why doing it once serves both.

Halves stay TRANSPARENT rather than floor-backed: they are composited onto whatever ground each
of the two cells has, through the same `overlay` the room decor uses.
"""
import os
from PIL import Image

CELL = 16
OUT = 'client/sprites/tall32'
SHEET = 'client/sprites/darkcave/dark cave_tiles_and_sprite_16x16.png'

# name -> the TOP cell; the bottom is the cell directly beneath it
TALL = {
    'lantern':  (19, 5),
    'lantern2': (20, 5),
    'shrub':    (17, 3),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    im = Image.open(SHEET).convert('RGBA')
    n = 0
    for name, (cx, cy) in sorted(TALL.items()):
        for half, dy in (('top', 0), ('bot', 1)):
            t = im.crop((cx * CELL, (cy + dy) * CELL, (cx + 1) * CELL, (cy + dy + 1) * CELL))
            ink = sum(1 for p in t.getdata() if p[3] > 32)
            if ink < 20:
                raise SystemExit('%s %s is nearly empty (%d px) - wrong cell?' % (name, half, ink))
            t.resize((32, 32), Image.NEAREST).save(os.path.join(OUT, '%s_%s.png' % (name, half)))
            n += 1
        print('  %-10s top (%d,%d) + bottom (%d,%d)' % (name, cx, cy, cx, cy + 1))
    print('baked %d halves for %d tall props -> %s' % (n, len(TALL), OUT))


if __name__ == '__main__':
    main()
