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
LANDMARKS = {
    # A candle burning on a stone plinth: an offering, and unmistakably furniture rather than
    # something to pick up. Three frames, so a shrine flickers the way the braziers do.
    'shrine': ('green_dungeon', [(12, 11), (13, 11), (14, 11)]),
    # A skull on the floor. The Elite Den spawns the dungeon's boss type as a mini-boss, and a
    # skull says "something big lives here" without looking like loot -- which a dropped weapon,
    # the other candidate, very much would.
    'elite_den': ('green_dungeon', [(13, 5)]),
}


def cell(pack, cx, cy):
    path = os.path.join(RAVEN, pack, 'All Tileset', '16x16.png')
    im = Image.open(path).convert('RGBA')
    return im.crop((cx * 16, cy * 16, (cx + 1) * 16, (cy + 1) * 16))


def bake_cell(src, name, frame):
    """2x to the 32px cell -- a whole-number factor, so the pixel grid survives."""
    floor = floor_tile()
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
        for frame, (cx, cy) in enumerate(cells):
            src = cell(pack, cx, cy)
            # A landmark that is nearly empty is a mis-typed coordinate, not art. This is the
            # check that would have caught a bad cell reference before it reached a player.
            n = ink(src)
            if n < 40:
                raise SystemExit('%s frame %d (%s %d,%d) has only %d opaque px - wrong cell?'
                                 % (name, frame, pack, cx, cy, n))
            dest = bake_cell(src, name, frame)
            print('baked %-16s frame %d  <- %s (%d,%d)  %d px of art' % (name, frame, pack, cx, cy, n))
    print('\nRemember: add/adjust the frame count in DungeonSprites.TILE_FRAMES.')
