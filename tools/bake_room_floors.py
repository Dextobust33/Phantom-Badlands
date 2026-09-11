"""Bake the ROOM FLOOR tiles, one look per pack, from the Raven tilesets.

Owner's design: each room picks its own look, so a floor drawn from a wide pool of packs gives
"variety and exploration, seeing things no other players have before" combinatorially rather than
by hand-authoring rooms.

HOW THE CELLS WERE CHOSEN, because it is not by eye and not purely by number either:

  1. Every pack was scanned for cells that are fully opaque, not blown out, not busy (a high
     colour spread means an object, not ground).
  2. Survivors were gated on CONTRAST WITH THE WALL RIM, not with the corridor floor. Coherence
     is explicitly not the goal -- the owner ruled rooms should be "unique and fun" -- but a
     player must always be able to see where the walls are. That is legibility, and it is the one
     hard constraint. 16 of 19 packs had a floor that passed.
  3. Contrast is a GATE, never the thing maximised. Maximising it returns the brightest cell in
     the sheet, which is a roof or a lit object; a first pass did exactly that and returned the
     same near-white orange for four different packs.
  4. Then the survivors were RENDERED beside the wall rim and looked at, which is what caught
     what no measurement could: the top-scoring cell for `beach_ocean_and_shore` and
     `miners_cave` is WATER, and for `shroom_chasm` it is a boulder. A tile can be opaque,
     mid-bright, low-spread, high-contrast -- and still not be a floor.

So the list below is curated from a measured shortlist. That is the same procedure that found
CAVE_FLOOR, and the reason this file records it is that picking a sheet cell by eye has already
covered a room in black notches once.

USAGE
    python tools/bake_room_floors.py            # bake them all
"""
import colorsys
import glob
import os
import re

from PIL import Image

CELL = 16
OUT = 'client/sprites/room_floor32'
TILES_GD = 'client/dungeon_tiles.gd'
RAVEN = 'client/sprites/raven'

# pack -> the cells that make up that pack's floor. More than one cell means the pack ships
# variation and the tile carries a MOTIF that would otherwise grid visibly across a chamber;
# a flat tile needs only one, because a flat fill cannot show a repeat.
FLOORS = {
    'shroom_chasm':    [(4, 2), (5, 2), (4, 3), (5, 3)],   # textured grey stone, 4 variants
    'the_underworld':  [(12, 3)],                          # dark violet, speckled
    'red_desert_ruin': [(5, 10)],                          # orange tiling - bricks are meant to repeat
    'farmlands_v3':    [(5, 0)],                           # grass
    'green_dungeon':   [(1, 0)],                           # mossy stone
    'winter_forest':   [(11, 9)],                          # pale sand
    # `interiors` was in this list and is not any more. Its best floor (#666532) sits 0.021
    # in hue and 0.082 in value from the CORRIDOR floor, so a room built from it barely read
    # as a room at all -- visible immediately once two chambers were rendered side by side.
    # Its only cells that pass both gates are bright red and orange, which are roof tiles and
    # carpets rather than ground. One fewer pack beats a forced bad choice.
    'cozy_home':       [(4, 11)],                          # timber
}


def sheet_for(pack):
    hits = (glob.glob(os.path.join(RAVEN, pack, 'All Tileset', '16*16.png'))
            + glob.glob(os.path.join(RAVEN, pack, 'All Tileset', 'Tileset.png')))
    if not hits:
        raise SystemExit('no tileset found for %s' % pack)
    return hits[0]


def _mean_hsv(img, require_opaque=True):
    vals = [p[:3] for p in img.convert('RGBA').getdata() if p[3] == 255]
    if not vals:
        return None
    if require_opaque and len(vals) < img.size[0] * img.size[1]:
        return None
    mean = tuple(sum(v[i] for v in vals) / len(vals) for i in range(3))
    return colorsys.rgb_to_hsv(*[c / 255 for c in mean]), mean


def _reference_image(sheet_const, cell_const, size):
    src = open(TILES_GD, encoding='utf-8').read()
    sheet = re.search(r'const %s := "([^"]+)"' % sheet_const, src).group(1).replace('res://', '')
    cx, cy = re.search(r'const %s := Vector2i\((\d+), (\d+)\)' % cell_const, src).groups()
    im = Image.open(sheet).convert('RGBA')
    return im.crop((int(cx) * size, int(cy) * size, (int(cx) + 1) * size, (int(cy) + 1) * size))


def _reference(sheet_const, cell_const, size, require_opaque=True):
    """The corridor floor / wall rim as the GAME defines them, read from dungeon_tiles.gd.

    Never copied here: a second copy of a constant is the shape that causes most of the
    wrong-text bugs in this repo, and it would let this check drift from what is drawn."""
    src = open(TILES_GD, encoding='utf-8').read()
    sheet = re.search(r'const %s := "([^"]+)"' % sheet_const, src).group(1).replace('res://', '')
    cx, cy = re.search(r'const %s := Vector2i\((\d+), (\d+)\)' % cell_const, src).groups()
    im = Image.open(sheet).convert('RGBA')
    crop = im.crop((int(cx) * size, int(cy) * size, (int(cx) + 1) * size, (int(cy) + 1) * size))
    return _mean_hsv(crop, require_opaque)


# The two legibility gates, as numbers rather than opinions.
# The wall rim is strongly brown-saturated, so a floor separates from it by HUE just as well as
# by brightness. Requiring brightness alone rejected `shroom_chasm` (value 0.30 against rock 0.24)
# -- the tile already shipped, which the owner looked at and called fine: "The room floor looks
# okay". The measurement was wrong and the eye was right. A blue-grey floor against brown rock is
# unmistakable at any brightness.
MIN_WALL_VALUE_GAP = 0.12
MIN_WALL_HUE_GAP = 0.10
MIN_CORR_HUE_GAP = 0.08        # below BOTH of these, a room does not read as a different space
MIN_CORR_VALUE_GAP = 0.12


def verify(pack, cell, tile):
    """Both gates, asserted at bake time so a new pack cannot quietly fail one.

    Gate 1 is against the WALL RIM: a player must always be able to see where the walls are.
    That is legibility and it is absolute.

    Gate 2 is against the CORRIDOR floor, and it exists because the first pool shipped a pack
    (`interiors`) whose floor was within 0.021 hue of the corridor -- perfectly legible against
    the walls, and yet the room did not read as a room. Variety is the whole point; a floor that
    looks like the passage you just walked down delivers none of it.
    """
    corr, _cm = _reference('SHEET_CAVE16', 'CAVE_FLOOR', 16)
    rock, _rm = _reference('SHEET_CAVE32', 'CAVE_ROCK', 32, require_opaque=False)
    got = _mean_hsv(tile)
    if got is None:
        raise SystemExit('%s %s is not fully opaque' % (pack, cell))
    (h, _s, v), _m = got

    wall_dh = min(abs(h - rock[0]), 1 - abs(h - rock[0]))
    if abs(v - rock[2]) < MIN_WALL_VALUE_GAP and wall_dh < MIN_WALL_HUE_GAP:
        raise SystemExit('%s %s fails the WALL gate: dValue %.3f dHue %.3f vs the rock rim - you '
                         'could not see where the walls are'
                         % (pack, cell, abs(v - rock[2]), wall_dh))
    dh = min(abs(h - corr[0]), 1 - abs(h - corr[0]))
    dv = abs(v - corr[2])
    if dh < MIN_CORR_HUE_GAP and dv < MIN_CORR_VALUE_GAP:
        raise SystemExit('%s %s fails the CORRIDOR gate: dHue %.3f dValue %.3f - the room would '
                         'not read as different from the passage' % (pack, cell, dh, dv))


def main():
    os.makedirs(OUT, exist_ok=True)
    # clear previous bakes so a removed pack does not leave orphans the loader still finds
    for old in glob.glob(os.path.join(OUT, '*.png')):
        os.remove(old)
    for old in glob.glob(os.path.join(OUT, '*.png.import')):
        os.remove(old)

    # The CORRIDOR floor as a standalone file. It is a sheet REGION everywhere else, which is
    # fine for drawing but useless to the compositor - `overlay` and `over_prop` need a file. The
    # two-cell props need it: half a lantern standing in a corridor has to be composited onto
    # something. Named `corridor_00` so it lives beside the room floors and loads the same way,
    # but it is deliberately NOT in ROOM_PACKS, so no room can ever pick it.
    #
    # Exempt from both legibility gates by definition: it IS the corridor, so "differs from the
    # corridor" is not a question that can be asked of it.
    corr_img = _reference_image('SHEET_CAVE16', 'CAVE_FLOOR', 16)
    corr_img.resize((32, 32), Image.NEAREST).save(os.path.join(OUT, 'corridor_00.png'))
    print('  %-18s the corridor floor, for compositing' % 'corridor')

    # The wall RIM and the VOID, for the same reason: both are sheet regions (or a fill) and the
    # compositor needs files. A two-cell prop standing at the edge of a space reaches its top half
    # into one of these. Prefixed `_` so `room_variants`, which scans `<pack>_NN.png`, can never
    # match them - they are not room floors and no room may pick one.
    _reference_image('SHEET_CAVE32', 'CAVE_ROCK', 32).save(os.path.join(OUT, '_rim.png'))
    Image.new('RGBA', (32, 32), (0, 0, 0, 255)).save(os.path.join(OUT, '_void.png'))
    print('  %-18s wall rim + void, for compositing' % 'rim/void')

    total = 0
    for pack, cells in sorted(FLOORS.items()):
        im = Image.open(sheet_for(pack)).convert('RGBA')
        for i, (cx, cy) in enumerate(cells):
            t = im.crop((cx * CELL, cy * CELL, (cx + 1) * CELL, (cy + 1) * CELL))
            if t.getextrema()[3][0] != 255:
                raise SystemExit('%s %d,%d is not opaque - a floor must be' % (pack, cx, cy))
            verify(pack, '%d,%d' % (cx, cy), t)
            # 2x to 32px, NEAREST: every dungeon cell asset is baked at 32 so a 64px cell is a
            # clean 2x, and pixel art at a smoothed scale is mush.
            t.resize((32, 32), Image.NEAREST).save(
                os.path.join(OUT, '%s_%02d.png' % (pack, i)))
            total += 1
        print('  %-18s %d tile(s) from %s' % (pack, len(cells), os.path.basename(sheet_for(pack))))
    print('baked %d room-floor tiles across %d packs -> %s' % (total, len(FLOORS), OUT))


if __name__ == '__main__':
    main()
