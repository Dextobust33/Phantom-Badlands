"""Bake the LANDMARK dungeon tiles (chests, lava, shrines, ...) from tileset cells.

WHY THIS EXISTS. `client/sprites/tile_floor32` was baked ad-hoc and its generator was never
committed, so the landmark art was irreplaceable DATA rather than reproducible OUTPUT -- the
same hole `bake_floor_backed.py` was written to close for the other bake dirs. It surfaced the
moment a landmark tile needed ADDING: owner 2026-09-10, "Shrines don't have a sprite and need
one", with no script to add one with.

THE SPECIAL ROOMS ARE A SET, AND THEY WERE HALF DONE. A floor can hold a Shrine, a Rest room,
an Elite Den or a Gamble Cache. Only Rest had art; the other three fell back to a coloured
letter. Worse, the ELITE DEN's letter was a character the bake font cannot draw, so it baked
the font's missing-glyph box -- which is what the owner actually saw and read, reasonably, as
"Elite monsters don't have a sprite". See `verify_dungeon_art.gd` for the gate that now makes a
tofu bake impossible to ship.

SOURCES are cells of the Raven 16px "All Tileset" sheets -- the same sheets the room floors and
decor come from, so a landmark reads at the scale everything else in the dungeon uses. Cells
were picked from a standalone-object scan (an object that runs into its neighbour is a fragment,
not a tile) and then looked at, because "small and standalone" in a tileset usually means ITEM,
and this game draws real loot on the floor.

USAGE
    python tools/bake_landmark_tiles.py            # bake every entry below
"""
import os

from PIL import Image

from bake_floor_backed import TILE, floor_tile

RAVEN = 'client/sprites/raven'
OUT = 'client/sprites/tile_floor32'

# name -> (pack, [(cell_x, cell_y), ...])   one entry per ANIMATION FRAME
#
# A frame may name a MULTI-CELL region as (x, y, w, h). That is not a nicety: the tileset's
# chests are 2x2, and taking one cell of one gives you a chest fragment -- the exact trap the
# decor baker documents ("they render as half of a lamppost"). The standalone test below is what
# catches it, by noticing that a cell's art runs off its edge into the neighbour's.
LANDMARKS = {
    # A candle burning on a stone plinth: an offering, and unmistakably furniture rather than
    # something to pick up. Three frames, so a shrine flickers the way the braziers do.
    'shrine': ('green_dungeon', [(12, 11), (13, 11), (14, 11)]),
    # A skull on the floor. The Elite Den spawns the dungeon's boss type as a mini-boss, and a
    # skull says "something big lives here" without looking like loot -- which a dropped weapon,
    # the other candidate, very much would.
    'elite_den': ('green_dungeon', [(13, 5)]),
    # A locked purple-and-gold chest, deliberately NOT the brown one `treasure` uses: a Gamble
    # Cache is big-or-nothing, and it should not be mistaken for an ordinary chest. Owner
    # 2026-09-10: "The Jackpot Gamble also doesn't have a sprite." 2x2 in the sheet -- one cell
    # of it is a chest fragment, which the edge test below refuses.
    'gamble_cache': ('green_dungeon', [(22, 9, 2, 2)]),
}


def cell(pack, spec):
    """One tileset cell, or a (x, y, w, h) region of them."""
    path = os.path.join(RAVEN, pack, 'All Tileset', '16x16.png')
    im = Image.open(path).convert('RGBA')
    cx, cy = spec[0], spec[1]
    w, h = (spec[2], spec[3]) if len(spec) == 4 else (1, 1)
    return im.crop((cx * 16, cy * 16, (cx + w) * 16, (cy + h) * 16))


def joins_neighbour(pack, spec):
    """Does this region's art run off its own edge? Then it is a FRAGMENT, not a tile.

    Checked on the region as cropped: opaque pixels along an outer edge mean the object
    continues into the cell beyond it. Baking that gives you half a chest."""
    reg = cell(pack, spec)
    px = reg.load()
    w, h = reg.size
    left = sum(1 for y in range(h) if px[0, y][3] > 40)
    right = sum(1 for y in range(h) if px[w - 1, y][3] > 40)
    top = sum(1 for x in range(w) if px[x, 0][3] > 40)
    hits = []
    if left > h * 0.6:
        hits.append('left')
    if right > h * 0.6:
        hits.append('right')
    if top > w * 0.6:
        hits.append('top')
    return hits


def bake_cell(src, name, frame):
    """Up to the 32px cell on a WHOLE-number factor, so the pixel grid survives. A 16px cell
    doubles; a 2x2 region is already 32px and goes 1:1."""
    floor = floor_tile()
    if TILE % src.size[0] or TILE % src.size[1]:
        raise SystemExit('%s frame %d is %dx%d - not a whole-number fit to the %dpx cell'
                         % (name, frame, src.size[0], src.size[1], TILE))
    spr = src.resize((TILE, TILE), Image.NEAREST)
    out = floor.copy()
    out.alpha_composite(spr, (0, 0))
    if out.getextrema()[3][0] != 255:
        raise SystemExit('%s frame %d is not fully opaque' % (name, frame))
    os.makedirs(OUT, exist_ok=True)
    dest = os.path.join(OUT, '%s_%d.png' % (name, frame))
    out.save(dest)
    return dest


def ink(img):
    return sum(1 for p in img.split()[3].get_flattened_data() if p > 40)


if __name__ == '__main__':
    for name, (pack, cells) in sorted(LANDMARKS.items()):
        for frame, spec in enumerate(cells):
            cut = joins_neighbour(pack, spec)
            if cut:
                raise SystemExit('%s frame %d (%s %s) runs off its %s edge - that is a FRAGMENT '
                                 'of a bigger object, widen the region'
                                 % (name, frame, pack, spec, '/'.join(cut)))
            src = cell(pack, spec)
            # A landmark that is nearly empty is a mis-typed coordinate, not art. This is the
            # check that would have caught a bad cell reference before it reached a player.
            n = ink(src)
            if n < 40:
                raise SystemExit('%s frame %d (%s %s) has only %d opaque px - wrong cell?'
                                 % (name, frame, pack, spec, n))
            bake_cell(src, name, frame)
            print('baked %-16s frame %d  <- %s %-12s %d px of art'
                  % (name, frame, pack, str(spec), n))
    print('\nRemember: add/adjust the frame count in DungeonSprites.TILE_FRAMES.')
