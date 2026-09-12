"""Bake the overworld's tile art: a ground per biome, and a transparent glyph per tile type.

WHY THIS EXISTS. Phase 2.95 PHASE 2 sprites the overworld, and the overworld has 67 tile types
across 6 biomes. Drawing all of them by hand before anything can be rendered would mean the
feature ships in one enormous step, or not at all. So every type gets a tile from DAY ONE - its
own glyph, in its own colour, rendered as an image - and real art replaces them one at a time
without the renderer changing at all. That is exactly what `client/sprites/glyph_floor32` did for
the dungeon, and it is why the dungeon could ship with art for eleven props and letters for the
rest without looking broken.

TWO LAYERS, NOT ONE. The dungeon pre-composites each sprite onto its floor because BBCode cannot
composite two images into one cell. The overworld renderer composes the whole grid into a SINGLE
image (the pattern `client/sanctuary_room.gd` already uses), so it can layer at compose time.
That means a ground per biome and a TRANSPARENT glyph per type - 6 + 67 + overlays instead of
6 x 67 - and a tile automatically looks right in every biome.

THE TABLE IS SCRAPED, NEVER RETYPED. Characters and colours come out of
`shared/world_system.gd::TILE_RENDER` and `BIOME_EMPTY_COLORS`. A hand-copied list is how the
dungeon's first glyph bake missed all 41 theme-legend entries.

NEVER BAKE A CHARACTER THE FONT CANNOT DRAW. Owner 2026-09-10 reported "Elite monsters don't have
a sprite" and what was on screen was a missing-glyph box baked into a tile. Coverage is asserted
against a private-use codepoint that no font has: if a character renders the same as that, the
font is drawing .notdef and the bake is refused.

USAGE
    python tools/bake_overworld_tiles.py            # bake everything
    python tools/bake_overworld_tiles.py --check    # report coverage, write nothing
"""
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

SRC = 'shared/world_system.gd'
OUT = 'client/sprites/overworld32'
TILE = 32
TARGET_H = 18                      # px of ink, matching the dungeon's glyph tiles
NOTDEF = '\ue123'                  # private use: no font has it, so it renders .notdef

# Consolas first, because it is what the map has always been read in. Segoe UI Symbol carries the
# handful of shapes Consolas does not.
FONTS = [r'C:\Windows\Fonts\consola.ttf', r'C:\Windows\Fonts\seguisym.ttf']

# REAL ART, cut from the Raven packs. Owner 2026-09-11, on seeing the glyph fallback:
# *"We should have enough sprites that glyphs shouldn't be needed."* So this is the table that
# matters; the glyph bake below is now the last resort for anything not yet cut, not the plan.
#
# Each entry is (pack, row, col) into that pack's `All Tileset/32x32.png`, picked by eye off
# `tools/tileset_contact_sheet.py`, which renders a sheet with its row and column numbers on it.
# Coordinates rather than names because the sheets have none - and written down here, once, so
# the next person can see the sheet and check the pick rather than re-deriving it.
CUTS = {
    # --- ground, one per biome ---------------------------------------------------------
    'ground:forest':   ('green_forest_v2', 1, 8),
    'ground:plains':   ('farmlands_v3', 0, 0),
    'ground:desert':   ('red_rock_desert', 1, 1),
    'ground:snow':     ('winter_forest', 1, 0),
    'ground:mountain': ('miners_cave', 2, 3),
    'ground:swamp':    ('green_forest_v2', 0, 11),

    # --- the land itself ---------------------------------------------------------------
    # NOTE: `empty` gets no entry ON PURPOSE. Empty IS the biome ground - giving it a prop put a
    # tuft of grass on every bare tile in the world and hid the ground it was meant to show.
    'tile:path':       ('farmlands_v3', 2, 4),
    'tile:wall':       ('winter_forest', 7, 14),
    'tile:bridge':     ('miners_cave', 6, 4),
    'tile:floor':      ('miners_cave', 2, 6),
    'tile:water':      ('beach_ocean_and_shore', 1, 27),
    'tile:deep_water': ('beach_ocean_and_shore', 3, 27),

    # --- gatherables. Owner: *"We will want sprites for all of the gatherables as well"* ---
    # a whole tree, shrunk from its 3x3 block - see cut_from_pack's note on span
    'tile:tree':         ('green_forest_v2', 5, 0, (3, 3)),
    'tile:stone':        ('green_forest_v2', 0, 4),
    'tile:ore_vein':     ('miners_cave', 6, 5),
    'tile:bush':         ('green_forest_v2', 1, 9),
    'tile:dense_brush':  ('green_forest_v2', 1, 11),
    'tile:herb':         ('green_forest_v2', 1, 13),
    'tile:flower':       ('green_forest_v2', 1, 12),
    'tile:reed':         ('green_forest_v2', 1, 10),
    'tile:brambleberry': ('farmlands_v3', 2, 29),
    'tile:cactus':       ('red_rock_desert', 4, 4),
    'tile:ice_bloom':    ('winter_forest', 5, 6),
    'tile:mushroom':     ('shroom_chasm', 5, 2),
    'tile:swamp_lily':   ('shroom_chasm', 6, 3),
    'tile:mountain_herb':('green_forest_v2', 11, 5),
}


def cut_from_pack(pack, row, col, dest, span=None, opaque=False):
    """One cell, or a REGION of cells shrunk to one.

    `span=(rows, cols)` takes a block and scales it down to 32x32. Raven draws a tree across
    three cells by three, because its games are walked through at close range; an overworld tile
    is a whole tree seen from far off. Cutting a single cell out of one gives a fragment - the
    first `tile:tree` pick was the middle of a canopy and read as a bracket - so the block is
    taken whole and shrunk."""
    from PIL import Image as _I
    sheet = _I.open(find_sheet(pack)).convert('RGBA')
    cols = sheet.size[0] // TILE
    rows = sheet.size[1] // TILE
    if row >= rows or col >= cols:
        raise SystemExit('%s has %dx%d cells; (%d,%d) is outside it' % (pack, cols, rows, row, col))
    if span is None:
        cell = sheet.crop((col * TILE, row * TILE, (col + 1) * TILE, (row + 1) * TILE))
    else:
        sr, sc = span
        if row + sr > rows or col + sc > cols:
            raise SystemExit('%s: region (%d,%d)+%dx%d runs off the sheet' % (pack, row, col, sr, sc))
        cell = sheet.crop((col * TILE, row * TILE, (col + sc) * TILE, (row + sr) * TILE))
        # LANCZOS keeps a canopy readable where NEAREST would alias it into noise.
        cell = cell.resize((TILE, TILE), _I.LANCZOS)
    if cell.getbbox() is None:
        raise SystemExit('%s (%d,%d) is EMPTY - a blank cell would draw a hole, which is the '
                         'fault the glyph fallback exists to prevent' % (pack, row, col))
    if opaque:
        # GROUND-class tiles must cover the cell completely. Raven draws a body of water as a
        # rounded block, so its corners are transparent - and the biome ground underneath then
        # shows through as a green rim around every deep-water tile. Fill the gaps with the
        # cell's own commonest colour rather than hunting for a cell that happens to be square.
        counts = {}
        for px in cell.getdata():
            if px[3] > 200:
                counts[px[:3]] = counts.get(px[:3], 0) + 1
        if not counts:
            raise SystemExit('%s (%d,%d) has no opaque pixel to take a fill colour from'
                             % (pack, row, col))
        fill = max(counts.items(), key=lambda kv: kv[1])[0] + (255,)
        base = _I.new('RGBA', cell.size, fill)
        base.alpha_composite(cell)
        cell = base
    cell.save(dest)


def find_sheet(pack):
    for name in ('32x32.png', '32X32.png', 'Tileset.png'):
        q = os.path.join(RAVEN_DIR, pack, 'All Tileset', name)
        if os.path.exists(q):
            return q
    raise SystemExit('no All Tileset sheet for %r' % pack)


RAVEN_DIR = 'client/sprites/raven'

# The overlays the map draws that are not tile types. Their meanings come from `_map_cells`.
OVERLAYS = {
    'dungeon': ('D', 'A335EE'),
    'corpse': ('X', 'FF0000'),
    'bounty': ('?', 'FFD700'),
    'sack': ('$', 'FFD700'),
    'threat': ('!', 'FFAA00'),
    'hot': ('!', 'FF0000'),
    'merchant': ('$', 'FFD700'),
}


def scrape_tiles(src):
    """(char, colour) per tile type, out of TILE_RENDER itself."""
    i = src.index('const TILE_RENDER')
    seg = src[i:src.index('\n}', i)]
    rows = re.findall(r'^\t"([a-z_]+)":\s*\{\s*"char":\s*"((?:[^"\\]|\\.)*)",\s*"color":\s*"#([0-9A-Fa-f]{6})"', seg, re.M)
    out = {}
    for name, ch, col in rows:
        out[name] = (ch.replace('\\"', '"').replace('\\\\', '\\'), col)
    return out


def scrape_biomes(src):
    """Biome name -> ground colour.

    The table is keyed by CONSTANTS (`BIOME_PLAINS:`), not by string literals, so the constants
    have to be resolved first. Reading it any other way means writing the six names down a second
    time, and then they are a second source of truth."""
    names = dict(re.findall(r'^const (BIOME_[A-Z]+)\s*=\s*"([a-z_]+)"', src, re.M))
    i = src.index('const BIOME_EMPTY_COLORS')
    seg = src[i:src.index('\n}', i)]
    out = {}
    for const_name, col in re.findall(r'(BIOME_[A-Z]+):\s*"#([0-9A-Fa-f]{6})"', seg):
        if const_name not in names:
            raise SystemExit('BIOME_EMPTY_COLORS names %s, which is not declared as a biome '
                             'constant - the table and the constants have drifted' % const_name)
        out[names[const_name]] = col
    return out


def render_mask(font, ch, box=64):
    im = Image.new('L', (box, box), 0)
    ImageDraw.Draw(im).text((box // 2, box // 2), ch, font=font, fill=255, anchor='mm')
    return im


def pick_font(ch):
    """The first font that draws this character as something other than .notdef."""
    for path in FONTS:
        if not os.path.exists(path):
            continue
        probe = ImageFont.truetype(path, 32)
        if render_mask(probe, ch).tobytes() != render_mask(probe, NOTDEF).tobytes():
            return path
    return None


def sized_font(path, ch):
    """Scale so the INK is TARGET_H tall, so every glyph reads at the same weight."""
    size = 24
    for _ in range(12):
        f = ImageFont.truetype(path, size)
        bb = render_mask(f, ch).getbbox()
        if bb is None:
            return None
        h = bb[3] - bb[1]
        if h == 0:
            return None
        if abs(h - TARGET_H) <= 1:
            return f
        size = max(6, int(round(size * TARGET_H / h)))
    return ImageFont.truetype(path, size)


def bake_glyph(ch, hexcol, dest):
    """One transparent 32x32 glyph. The renderer lays it over whichever ground the biome gives."""
    path = pick_font(ch)
    if path is None:
        return False
    f = sized_font(path, ch)
    if f is None:
        return False
    col = tuple(int(hexcol[i:i + 2], 16) for i in (0, 2, 4))
    im = Image.new('RGBA', (TILE, TILE), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # The drop shadow is what makes a glyph read against ground of any brightness.
    d.text((TILE // 2 + 1, TILE // 2 + 1), ch, font=f, fill=(0, 0, 0, 200), anchor='mm')
    d.text((TILE // 2, TILE // 2), ch, font=f, fill=col + (255,), anchor='mm')
    im.save(dest)
    return True


def bake_ground(hexcol, dest):
    """A biome's bare ground. Flat for now, and deliberately: it is the layer most obviously
    improved by real art later, and the renderer does not change when it is."""
    col = tuple(int(hexcol[i:i + 2], 16) for i in (0, 2, 4))
    im = Image.new('RGBA', (TILE, TILE), col + (255,))
    d = ImageDraw.Draw(im)
    # A faint speckle, so a field of ground does not read as a solid block of colour.
    for n in range(26):
        x = (n * 7 + 3) % TILE
        y = (n * 11 + 5) % TILE
        shade = 10 if (n % 2) else -10
        px = tuple(max(0, min(255, c + shade)) for c in col)
        d.point((x, y), fill=px + (255,))
    im.save(dest)


def main():
    check_only = '--check' in sys.argv
    src = open(SRC, encoding='utf-8').read()
    tiles = scrape_tiles(src)
    biomes = scrape_biomes(src)
    print('scraped %d tile types and %d biomes from %s' % (len(tiles), len(biomes), SRC))

    # Refuse the whole bake if any character is un-drawable, rather than quietly baking tofu.
    missing = [n for n, (ch, _) in tiles.items() if pick_font(ch) is None]
    missing += ['overlay:' + n for n, (ch, _) in OVERLAYS.items() if pick_font(ch) is None]
    if missing:
        raise SystemExit('no available font can draw: %s - baking would produce the '
                         'missing-glyph box, which is the exact bug this refuses to repeat'
                         % ', '.join(missing))
    print('every character is drawable by an available font')

    if check_only:
        print('--check: nothing written')
        return

    os.makedirs(os.path.join(OUT, 'ground'), exist_ok=True)
    os.makedirs(os.path.join(OUT, 'tile'), exist_ok=True)
    os.makedirs(os.path.join(OUT, 'overlay'), exist_ok=True)

    for biome, col in sorted(biomes.items()):
        bake_ground(col, os.path.join(OUT, 'ground', biome + '.png'))
    print('baked %d biome grounds' % len(biomes))

    cut = 0
    for key, spec in sorted(CUTS.items()):
        kind, name = key.split(':', 1)
        pack, row, col = spec[0], spec[1], spec[2]
        span = spec[3] if len(spec) > 3 else None
        # ground-class tiles must not let the biome show through - see cut_from_pack
        opaque = kind == 'ground' or name in ('water', 'deep_water', 'path', 'floor', 'wall')
        cut_from_pack(pack, row, col, os.path.join(OUT, kind, name + '.png'), span, opaque)
        cut += 1
    print('cut %d tiles from real art' % cut)

    have_art = set(k.split(':', 1)[1] for k in CUTS if k.startswith('tile:'))
    n = 0
    for name, (ch, col) in sorted(tiles.items()):
        if name in have_art:
            continue
        if bake_glyph(ch, col, os.path.join(OUT, 'tile', name + '.png')):
            n += 1
    print('%d tiles still on a glyph, waiting for art' % n)

    m = 0
    for name, (ch, col) in sorted(OVERLAYS.items()):
        if bake_glyph(ch, col, os.path.join(OUT, 'overlay', name + '.png')):
            m += 1
    print('baked %d overlay glyphs' % m)
    print('%d files in %s' % (len(biomes) + n + m, OUT))


if __name__ == '__main__':
    main()
