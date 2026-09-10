"""Bake per-pack ROOM DECOR from each pack's 16px tileset.

SOURCE NOTE, and it is not the obvious one. Each pack ships an RPG Maker "B" object sheet with
2,304 cells, which looks like the right source until you measure the grid: RPG Maker MV/MZ tiles
are 48px, so that sheet is 16x16 objects at 48px, not 48x48 at 16px. Slicing it at 16 cut every
object into nine fragments, which is why a first run returned almost nothing -- the standalone
test below correctly rejected fragments. And 48px art scaled to our 32px tile is a 2/3 ratio,
which is mush beside floors drawn at a clean 2x. So decor comes from the SAME 16px "All Tileset"
sheet the floors do, where the art is at the scale everything else in the dungeon uses.

Layer three of the owner's design: *"a random pack for the floors, a random pack for the walls,
and a random pack for decor items... We could even do doors or chests and things to break it up."*
Decor is the layer that does the most work -- it is what makes a room read as a mushroom cave
rather than a mine -- and it is by far the best supported: every pool pack ships a 768x768 object
sheet, 2,304 cells each.

THE TRAP THIS AVOIDS, which has already been sprung once. The scatter props were first taken
straight off a tileset and two of them turned out to be the LOWER HALVES of a lantern and a piece
of a tent, which read as debris on their own. Owner: *"the two lanterns you added in those are
actually two vertical squares tall... currently they render as half of a lamppost."*

So a cell is only usable as one-cell decor if the object it contains does NOT continue into a
neighbouring cell. That is testable: an object that runs off the edge of its cell has opaque
pixels ON that edge, and its neighbour has opaque pixels on the touching edge. Both are checked
below. A cell whose art touches an edge that its neighbour also fills is rejected as a fragment.

USAGE
    python tools/bake_room_decor.py            # bake for every pack in FLOORS
"""
import glob
import os

from PIL import Image

CELL = 16
OUT = 'client/sprites/decor32'
RAVEN = 'client/sprites/raven'

# CURATED, not auto-picked, and the reason is worth recording. The automatic shortlist optimised
# for "small, low in the cell, standalone" -- and in a tileset, small objects are ITEMS. It
# returned CHICKENS for farmlands_v3, daggers and glowing skulls for the_underworld, and crates
# and kitchen pots for cozy_home. This game already draws real loot and real monsters as floor
# sprites, so decor that looks like a sword or a bird is not merely ugly, it is misleading. It is
# the same lesson the scatter props learned when a SKULL was dropped for reading as a pickup:
# background scatter must stay in the background.
#
# 2,304 object cells per pack was a count of CELLS, not of usable scenery. Three packs have any:
DECOR = {
    'shroom_chasm':  [(7, 12), (7, 14), (9, 15), (20, 0), (7, 15), (21, 2)],   # flower, crystals, sand
    'winter_forest': [(1, 0), (6, 6), (7, 6)],                                 # rock, twigs, branch
    'green_dungeon': [(10, 3), (11, 3), (7, 11), (8, 11)],                     # flowers, stone, log
}
# Rooms whose pack is NOT in DECOR keep the existing darkcave scatter props, which are neutral
# and already work. A pack contributing a floor need not contribute decor.
PACKS = sorted(DECOR)

MAX_PER_PACK = 16          # enough for variety, few enough to eyeball before shipping
MIN_INK = 24              # px: below this the cell is a speck, not decor
MAX_INK_FRAC = 0.55       # above this it is a full tile, not an object standing on the floor


def object_sheet(pack):
    """The 16px tileset, NOT the RPG Maker B sheet - see the source note at the top."""
    hits = (glob.glob(os.path.join(RAVEN, pack, 'All Tileset', '16*16.png'))
            + glob.glob(os.path.join(RAVEN, pack, 'All Tileset', 'Tileset.png')))
    return hits[0] if hits else None


def cell_of(im, cx, cy):
    return im.crop((cx * CELL, cy * CELL, (cx + 1) * CELL, (cy + 1) * CELL))


def edge_opaque(tile, side):
    """Does the art reach this edge of the cell?"""
    px = tile.load()
    w, h = tile.size
    rng = range(w) if side in ('top', 'bottom') else range(h)
    for i in rng:
        if side == 'top' and px[i, 0][3] > 32:
            return True
        if side == 'bottom' and px[i, h - 1][3] > 32:
            return True
        if side == 'left' and px[0, i][3] > 32:
            return True
        if side == 'right' and px[w - 1, i][3] > 32:
            return True
    return False


OPPOSITE = {'top': 'bottom', 'bottom': 'top', 'left': 'right', 'right': 'left'}
OFFSET = {'top': (0, -1), 'bottom': (0, 1), 'left': (-1, 0), 'right': (1, 0)}


def is_standalone(im, cx, cy):
    """True when the object in this cell does not continue into a neighbour.

    Touching an edge is not disqualifying on its own -- plenty of art fills its cell. What
    disqualifies it is touching an edge WHOSE NEIGHBOUR also has art on the shared boundary,
    because that is the signature of one object spread across two cells.
    """
    tile = cell_of(im, cx, cy)
    cols, rows = im.size[0] // CELL, im.size[1] // CELL
    for side, (dx, dy) in OFFSET.items():
        if not edge_opaque(tile, side):
            continue
        nx, ny = cx + dx, cy + dy
        if not (0 <= nx < cols and 0 <= ny < rows):
            continue
        if edge_opaque(cell_of(im, nx, ny), OPPOSITE[side]):
            return False
    return True


def curated(pack):
    return DECOR.get(pack, [])


def pick(pack):
    sheet = object_sheet(pack)
    if not sheet:
        return []
    im = Image.open(sheet).convert('RGBA')
    cols, rows = im.size[0] // CELL, im.size[1] // CELL
    out = []
    for cy in range(rows):
        for cx in range(cols):
            t = cell_of(im, cx, cy)
            ink = sum(1 for p in t.getdata() if p[3] > 32)
            if ink < MIN_INK or ink > CELL * CELL * MAX_INK_FRAC:
                continue
            if not is_standalone(im, cx, cy):
                continue
            # prefer objects that sit low in the cell: decor rests ON the ground
            px = t.load()
            ys = [y for y in range(CELL) for x in range(CELL) if px[x, y][3] > 32]
            low = sum(ys) / len(ys) / CELL
            out.append((-low, (cx, cy), ink))
    out.sort()
    return [c for _s, c, _i in out[:MAX_PER_PACK]]


def main():
    os.makedirs(OUT, exist_ok=True)
    for old in glob.glob(os.path.join(OUT, '*.png')) + glob.glob(os.path.join(OUT, '*.png.import')):
        os.remove(old)
    total = 0
    for pack in PACKS:
        cells = curated(pack)
        im = Image.open(object_sheet(pack)).convert('RGBA')
        for i, (cx, cy) in enumerate(cells):
            t = cell_of(im, cx, cy).resize((32, 32), Image.NEAREST)
            t.save(os.path.join(OUT, '%s_%02d.png' % (pack, i)))
            total += 1
        print('  %-18s %d decor cells: %s' % (pack, len(cells), cells))
    print('baked %d decor tiles -> %s' % (total, OUT))


if __name__ == '__main__':
    main()
