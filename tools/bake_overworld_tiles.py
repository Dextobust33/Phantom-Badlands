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
import json
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
    # Not a biome: the floor INSIDE an NPC post. A post is a building, so what you stand on
    # there is its floor, not the snow or sand the building happens to sit in. Without this the
    # stations were drawn on the surrounding biome and every one wore a square of snow.
    'ground:post':     ('miners_cave', 2, 6),
    'ground:swamp':    ('green_forest_v2', 0, 11),

    # --- the land itself ---------------------------------------------------------------
    # NOTE: `empty` gets no entry ON PURPOSE. Empty IS the biome ground - giving it a prop put a
    # tuft of grass on every bare tile in the world and hid the ground it was meant to show.
    # ⚑ A ROAD, NOT A COLOUR. Owner 2026-09-13: *"Roads need actual sprites, the current
    # coloring looks bad."* It measured FLAT - pixel variance 0.0, saturation 0.66 - because
    # `farmlands_v3 (2,4)` is the plain centre fill of a dirt autotile, and `opaque=True` then
    # floods any gaps with its commonest colour. The result was a bright orange square.
    # Cobblestone reads as something built and maintained, which is what a road between posts is.
    'tile:path':       ('green_village', 17, 2),
    'tile:wall':       ('winter_forest', 7, 14),
    'tile:bridge':     ('miners_cave', 6, 4),

    # --- NPC POST STATIONS. The craft_stations pack was bought for exactly these. Each station
    # is drawn two or three cells across, so they are region cuts shrunk to one tile.
    'tile:forge':         ('craft_stations', 0, 0, (3, 2)),
    'tile:apothecary':    ('craft_stations', 3, 6, (2, 2)),
    'tile:workbench':     ('craft_stations', 5, 0, (2, 2)),
    'tile:enchant_table': ('craft_stations', 7, 1, (2, 1)),
    # ⚑ THESE TWO WERE HALVES OF ONE PICTURE.
    #
    # Owner 2026-09-13: *"The market and the sprite that say I'm fully rested seem to be parts of
    # the same sprite divided in half, doesn't look good."* Exactly right: `craft_stations` rows
    # 9 AND 10 together are a single fishmonger's stall - goods on top, counter underneath. The
    # market took the top row and the inn took the bottom, so the market was an awning with
    # nothing under it and the inn was a bare table.
    #
    # The market gets the whole stall now, and the inn gets a BED, which is what a place you rest
    # at should look like.
    'tile:market':        ('craft_stations', 9, 0, (2, 2)),
    'tile:inn':           ('cozy_home', 9, 0, (2, 2)),
    'tile:brazier':       ('craft_stations', 2, 6, (1, 2)),
    'tile:banner':        ('craft_stations', 5, 6, (2, 2)),
    'tile:writing_desk':  ('craft_stations', 7, 6, (2, 2)),

    # --- POST FURNITURE and decor, from the village pack ---------------------------------
    # ⚑ A DOOR IS NOT ONE CELL. `(6, 7)` is a FRAGMENT of the middle of a door - the real art is
    # the 3x2 block at (5,7): lintel, frame, panelling and handle. Owner 2026-09-13: *"I believe
    # post doors may suffer from the same problem."* They did.
    'tile:door':        ('green_village', 5, 7, (3, 2)),
    'tile:well':        ('green_village', 5, 0, (3, 2)),
    # ⚑ NOT THE SAME CELL AS `well`. Both named `(5, 0, (3,2))` - one copy-pasted line - so they
    # baked byte-identical and a player who built a well got a fountain. That block IS a well
    # (lintel, stone ring, bucket); the fountain is a separate water feature.
    'tile:fountain':    ('green_village', 2, 2),
    'tile:signpost':    ('green_village', 5, 5),
    'tile:quest_board': ('green_village', 4, 5),
    'tile:lamp_post':   ('green_village', 4, 0),
    'tile:torch':       ('green_village', 2, 6),
    'tile:crate':       ('green_village', 2, 0),
    'tile:storage':     ('green_village', 3, 0),
    'tile:cairn':       ('green_village', 1, 5),
    # ⚑ 13.0 FROM THE HEALER, AND THE SAME JOB. Both were orange-framed signs from neighbouring
    # cells of one sheet, so at 26px you could walk into the wrong station. The HEALER's yellow
    # cross reads correctly and is left alone; the smith gets a furnace, which is what a smith
    # works at. Measured: 13.0 -> 50.2 apart, and 33.4 from the nearest other station.
    'tile:blacksmith':  ('craft_stations', 1, 6, (2, 2)),
    'tile:healer':      ('green_village', 8, 13),
    'tile:hedge':       ('green_village', 5, 8),

    # --- the rest of the post decor, from the interiors pack ------------------------------
    'tile:lectern':  ('interiors', 3, 18),
    'tile:mosaic':   ('interiors', 0, 27),
    # `interiors (9,22)` carried 0.8% ink and drew an INVISIBLE tile - a craftable structure you
    # could place and not see. Replaced with a lit crystal pillar, which is what stone blocks and
    # magic dust ought to look like. Provisional: the owner is choosing from alternatives.
    'tile:pylon':    ('interiors', 6, 25),
    'tile:statue':   ('interiors', 9, 24),
    'tile:easel':    ('interiors', 4, 19),
    'tile:pedestal': ('interiors', 3, 25),
    'tile:bench':    ('interiors', 4, 11, (1, 2)),
    'tile:beehive':  ('honey_bee', 6, 0),
    'tile:throne':   ('honey_bee', 6, 10, (2, 1)),

    # --- the last of them: post structures, monuments and plots ---------------------------
    'tile:companion_stable': ('farmlands_v3', 16, 7, (3, 3)),
    'tile:cartographer':     ('interiors', 4, 17),
    'tile:tower':            ('sun_city', 16, 0, (3, 1)),
    'tile:guard':            ('sun_city', 20, 9),
    # The cross on a post reads as a scarecrow frame, which is what one is. The farm pack has no
    # scarecrow of its own - it has a windmill, which is a different thing.
    'tile:scarecrow':        ('green_village', 1, 4),
    # ⚑ 4.4 FROM THE QUEST BOARD. `(4,6)` and `quest_board`'s `(4,5)` are neighbouring cells of
    # one sheet, so the two were all but identical at the 26px the map draws - and they sit side
    # by side inside every post. A framed sign with a blue emblem measures 51 apart instead.
    'tile:post_marker':      ('green_village', 5, 14),
    'tile:garden_plot':      ('sun_city', 13, 17, (2, 2)),
    'tile:tent':             ('farmlands_v3', 14, 2, (2, 2)),
    'tile:cage':             ('farmlands_v3', 21, 15),
    'tile:shrine':           ('sun_city', 19, 5),
    'tile:totem':            ('sun_city', 19, 9),
    'tile:obelisk':          ('sun_city', 20, 5),
    'tile:sundial':          ('sun_city', 14, 15),
    'tile:birdbath':         ('farmlands_v3', 17, 18),

    # --- OVERLAYS as art too. Owner 2026-09-11: *"Dungeons markers should have a sprite, so
    # should corpses, bounties, hotzone we will want to do graphically rather than the glyph"*.
    'overlay:dungeon':  ('green_forest_v2', 2, 9),

    # --- DUNGEON ENTRANCES, one per family ------------------------------------------------
    # Owner 2026-09-13: *"dungeons on the over world should have a variety, not all the same
    # tile."* 53 dungeon types drew one marker. Grouped by what the way IN would look like -
    # see `DungeonDatabase.ENTRANCE_FAMILY` - because that is what you see from outside; tier is
    # already carried by the hover and the marker colour.
    'overlay:dungeon_cave':     ('green_forest_v2', 2, 9),
    'overlay:dungeon_crypt':    ('green_dungeon', 5, 3),
    'overlay:dungeon_fortress': ('green_village', 10, 9),
    'overlay:dungeon_temple':   ('sun_city', 18, 6),
    # `marsh` and `aerie` have NO ART YET and that is deliberate. The cells tried for them read
    # as an orange crate and a grey post - a marker that depicts the wrong thing is worse than a
    # generic one, because a player believes it. They fall back to the plain dungeon marker,
    # which is the path `_overlay_img` exists to provide, and the owner is picking replacements.
    'overlay:dungeon_thicket':  ('green_dungeon', 3, 9),
    'overlay:dungeon_rift':     ('green_dungeon', 4, 7),
    'overlay:corpse':   ('red_rock_desert', 5, 5),
    'overlay:bounty':   ('interiors', 6, 30),
    'overlay:hot':      ('green_forest_v2', 4, 11),
    'overlay:threat':   ('interiors', 6, 26),
    'overlay:sack':     ('green_forest_v2', 9, 9),
    'overlay:merchant': ('green_village', 7, 2, (2, 2)),
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


## The least ink a cell may carry and still be worth drawing. The thinnest REAL tile in the set
## (`stone`) is 30%; this sits well under it so a legitimately sparse pick is not rejected, while
## the 0.8% that shipped as an invisible pylon is.
MIN_INK_COVERAGE = 0.08


def cut_region_native(pack, row, col, span, dest):
    """A multi-cell region kept at its NATIVE size - 3x2 cells stay 96x64 pixels.

    The single-cell bake shrinks these, which is right for a minimap glyph and wrong for the map:
    a well drawn at a sixth of its resolution stops looking like a well. The renderer composes the
    whole grid into one image, so a tile bigger than its cell is already possible - that is what
    `FIGURE_SCALE` does for people - and this is the art to do it with."""
    from PIL import Image as _I
    sheet = _I.open(find_sheet(pack)).convert('RGBA')
    cols = sheet.size[0] // TILE
    rows = sheet.size[1] // TILE
    sr, sc = span
    if row + sr > rows or col + sc > cols:
        raise SystemExit('%s: region (%d,%d)+%dx%d runs off the sheet' % (pack, row, col, sr, sc))
    reg = sheet.crop((col * TILE, row * TILE, (col + sc) * TILE, (row + sr) * TILE))
    if reg.getbbox() is None:
        raise SystemExit('%s region (%d,%d) is EMPTY' % (pack, row, col))
    reg.save(dest)


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
    # ⚑ NOT-EMPTY IS NOT THE SAME AS VISIBLE, and the difference shipped.
    #
    # The check above only catches a cell that is literally all zero. `tile:pylon` pointed at
    # `interiors (9, 22)`, which carries a handful of stray pixels - 0.8% ink coverage against a
    # 30% minimum for every other tile in the set - so it passed this guard and then drew NOTHING
    # on the map. A player could craft a pylon, place it, and see bare grass.
    #
    # The question is not "is any pixel set", it is "would a player see a thing there", so the
    # guard measures coverage. Same lesson as the dungeon art gate: check the FUNCTION.
    ink = sum(1 for px in cell.getdata() if px[3] > 24)
    coverage = ink / float(cell.size[0] * cell.size[1])
    if coverage < MIN_INK_COVERAGE:
        raise SystemExit('%s (%d,%d) is only %.1f%% ink - it would draw an invisible tile. '
                         'Every other tile in the set is 30%% or more; pick a different cell.'
                         % (pack, row, col, coverage * 100.0))
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
    # The player and other players get a glyph here so no cell is ever blank. They are REPLACED
    # by real figure sprites when the renderer is given them - the overworld already has 80
    # player looks in `overworld_floor32` - but a marker that is always present beats a hole.
    'player': ('@', 'FFFF00'),
    'other': ('*', '00FFFF'),
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

    os.makedirs(os.path.join(OUT, 'big'), exist_ok=True)
    cut = 0
    big_manifest = {}
    for key, spec in sorted(CUTS.items()):
        kind, name = key.split(':', 1)
        pack, row, col = spec[0], spec[1], spec[2]
        span = spec[3] if len(spec) > 3 else None
        # ground-class tiles must not let the biome show through - see cut_from_pack
        opaque = kind == 'ground' or name in ('water', 'deep_water', 'path', 'floor', 'wall')
        cut_from_pack(pack, row, col, os.path.join(OUT, kind, name + '.png'), span, opaque)
        # ⚑ AND KEEP THE ART AT ITS REAL SIZE.
        #
        # Owner 2026-09-13: *"The samples you provided all look like multi tile artwork you've
        # attempted to break down into one. We should instead use the multitile art so they
        # appear as complete on the map with only a single base tile serving as the interactable
        # tile."*
        #
        # Right, and it is most of what was wrong with these tiles: `companion_stable` and `tree`
        # are 3x3 blocks shrunk into one 32px cell, which throws away 89% of the art and leaves a
        # smudge. The single-cell version is still baked - the minimap and any fallback want it -
        # but the renderer prefers this one and draws it across the cells it really occupies,
        # anchored to the base cell the player interacts with.
        if span is not None and kind == 'tile':
            sr, sc = span
            if sr > 1 or sc > 1:
                cut_region_native(pack, row, col, span,
                                  os.path.join(OUT, 'big', name + '.png'))
                big_manifest[name] = [sr, sc]
        cut += 1
    print('cut %d tiles from real art' % cut)
    with open(os.path.join(OUT, 'big', 'big_tiles.json'), 'w', encoding='utf-8') as f:
        json.dump(big_manifest, f, indent='	', sort_keys=True)
    print('%d tiles also kept at full size (up to %dx%d cells)' % (
        len(big_manifest),
        max([v[1] for v in big_manifest.values()] or [0]),
        max([v[0] for v in big_manifest.values()] or [0])))

    # `empty` IS the biome ground and `void` is a tile outside your sight: both draw the ground
    # and nothing else. Giving either one a tile put something on top of every bare square in the
    # world. They are listed here so a future reader sees the decision rather than a gap.
    NO_TILE = ('empty', 'void')
    have_art = set(k.split(':', 1)[1] for k in CUTS if k.startswith('tile:')) | set(NO_TILE)
    n = 0
    for name, (ch, col) in sorted(tiles.items()):
        if name in have_art:
            continue
        if bake_glyph(ch, col, os.path.join(OUT, 'tile', name + '.png')):
            n += 1
    print('%d tiles still on a glyph, waiting for art' % n)

    overlay_art = set(k.split(':', 1)[1] for k in CUTS if k.startswith('overlay:'))
    m = 0
    for name, (ch, col) in sorted(OVERLAYS.items()):
        if name in overlay_art:
            continue
        if bake_glyph(ch, col, os.path.join(OUT, 'overlay', name + '.png')):
            m += 1
    print('%d overlays still on a glyph' % m)
    print('%d files in %s' % (len(biomes) + cut + n + m, OUT))
    bake_tinted_markers(OUT)
    _assert_no_twins(OUT)
    _warn_adjacent_sources()
    print('no two tiles baked to the same picture')



## Dungeon families whose marker is the cave mouth RE-HUED rather than a cell of its own.
##
## Two of the eight had no art that read: every cell tried for `marsh` and `aerie` looked like an
## orange crate or a grey post, and a marker that depicts the wrong thing is worse than a generic
## one because a player believes it. Re-hueing the entrance keeps the one shape a player has
## already learned means "a way in" and changes only what KIND of way in it is - which is exactly
## what the family is for. The dark opening itself is left alone; only the rim is re-coloured.
TINTED_MARKERS = {
    'dungeon_marsh': (0.47, 0.85, 0.85),   # teal - waterlogged, sunken
    'dungeon_aerie': (0.58, 0.35, 1.15),   # pale blue-grey - cold and high
}


## Pairs that are the same picture ON PURPOSE, each with its reason. Anything not listed here is
## a copy-pasted spec line, which is how `well` and `fountain` became one image.
ALLOWED_PAIRS = {
    # `cave` is the DEFAULT family and `dungeon` is the fallback drawn when a family has no art
    # of its own, so the commonest kind of dungeon and the generic marker are deliberately the
    # same picture. Splitting them would make an unlisted dungeon type look like a specific
    # thing it is not.
    ('overlay/dungeon', 'overlay/dungeon_cave'),
}


def bake_tinted_markers(out_dir):
    """Derive the re-hued dungeon markers from the baked `dungeon` overlay.

    ⚑ GENERATED, NOT HAND-MADE. These two were first produced by a one-off script, which means a
    future bake would not reproduce them and nobody would know until they went stale. Anything the
    game ships has to come out of the build that builds everything else."""
    import colorsys
    from PIL import Image as _I
    src = os.path.join(out_dir, 'overlay', 'dungeon.png')
    if not os.path.exists(src):
        raise SystemExit('cannot tint markers: %s is missing' % src)
    base = _I.open(src).convert('RGBA')
    for name, (hue, sat_mul, val_mul) in sorted(TINTED_MARKERS.items()):
        im = base.copy()
        px = im.load()
        w, h = im.size
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                if a == 0:
                    continue
                hh, ss, vv = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
                if vv < 0.18:
                    continue          # the opening stays black - it is the hole
                nr, ng, nb = colorsys.hsv_to_rgb(hue, min(1.0, ss * sat_mul), min(1.0, vv * val_mul))
                px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)
        im.save(os.path.join(out_dir, 'overlay', name + '.png'))
    print('derived %d tinted dungeon marker(s)' % len(TINTED_MARKERS))


def _warn_adjacent_sources():
    """Flag any two tiles cut from ADJACENT regions of the same sheet.

    ⚑ THIS SHAPE CAUSED THREE BUGS IN ONE DAY. Adjacent cells in a tileset are almost always
    either two halves of ONE object or two near-identical variants of it:

      * `market` (row 9) and `inn` (row 10) were the top and bottom of a single fishmonger's
        stall - the market was an awning with nothing under it, the inn a bare table. Owner:
        "parts of the same sprite divided in half, doesn't look good."
      * `post_marker` (4,6) and `quest_board` (4,5) measured 4.4 apart at play size.
      * `blacksmith` (7,13) and `healer` (8,13), same JOB, 13.0 apart.

    Advisory rather than fatal: adjacency is sometimes fine, and a bake that refuses to run is
    worse than one that tells you where to look. The point is that nobody was looking."""
    # WITHIN ONE KIND only. Comparing a ground against a prop, or a marker against a tile, is
    # meaningless - they are never confused with each other and are routinely cut from
    # neighbouring cells of the same sheet on purpose. Including them took this from 10 pairs
    # worth reading to 42 that were mostly noise, which is how a useful advisory gets ignored.
    boxes = []
    for key, spec in sorted(CUTS.items()):
        kind, name = key.split(':', 1)
        pack, row, col = spec[0], spec[1], spec[2]
        span = spec[3] if len(spec) > 3 else (1, 1)
        boxes.append((pack, row, col, span[0], span[1], '%s:%s' % (kind, name), kind))
    hits = []
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            a, b = boxes[i], boxes[j]
            if a[0] != b[0] or a[6] != b[6]:
                continue
            # Pairs that are deliberately one picture are already documented in the twin check.
            if (a[5].replace('overlay:', 'overlay/'), b[5].replace('overlay:', 'overlay/')) in ALLOWED_PAIRS:
                continue
            if (b[5].replace('overlay:', 'overlay/'), a[5].replace('overlay:', 'overlay/')) in ALLOWED_PAIRS:
                continue
            # Touching or overlapping, in either axis.
            r_touch = a[1] < b[1] + b[3] + 1 and b[1] < a[1] + a[3] + 1
            c_touch = a[2] < b[2] + b[4] + 1 and b[2] < a[2] + a[4] + 1
            if r_touch and c_touch:
                hits.append('%s (%d,%d) and %s (%d,%d) in %s'
                            % (a[5], a[1], a[2], b[5], b[1], b[2], a[0]))
    if hits:
        print('ADVISORY - %d tile pair(s) cut from touching regions of one sheet:' % len(hits))
        for h in hits:
            print('    ' + h)
        print('  Adjacent cells are usually halves of one object or variants of it. Look at them.')
    else:
        print('no two tiles cut from touching regions')


def _assert_no_twins(out_dir):
    """No two tiles may bake to the SAME IMAGE.

    ⚑ `tile:well` and `tile:fountain` both named `green_village (5, 0, (3,2))` - one copy-pasted
    line - so they were byte-identical on disk and a player who built a well got a fountain. Both
    are craftable structures, so this was visible in the game. Nothing compared the OUTPUTS, only
    the inputs, and two inputs that are the same look perfectly reasonable one line apart."""
    import hashlib
    ALLOWED = ALLOWED_PAIRS
    _unused = {
        # `cave` is the DEFAULT family and `dungeon` is the fallback drawn when a family has no
        # art of its own, so the commonest kind of dungeon and the generic marker are deliberately
        # the same picture. Splitting them would mean an unlisted dungeon type looks like a
        # specific thing it is not.
        ('overlay/dungeon', 'overlay/dungeon_cave'),
    }
    twins = []
    # WITHIN a kind, not across kinds. `tile:floor` and `ground:post` are deliberately the same
    # picture - a trading post's floor IS its ground - and flagging that is noise, not a finding.
    # Two TILES sharing one picture is the fault this exists for.
    for kind in ('tile', 'ground', 'overlay'):
        d = os.path.join(out_dir, kind)
        if not os.path.isdir(d):
            continue
        seen = {}
        for f in sorted(os.listdir(d)):
            if not f.endswith('.png'):
                continue
            h = hashlib.md5(open(os.path.join(d, f), 'rb').read()).hexdigest()
            if h in seen:
                pair = (seen[h], '%s/%s' % (kind, f[:-4]))
                if pair not in ALLOWED and (pair[1], pair[0]) not in ALLOWED:
                    twins.append(pair)
            else:
                seen[h] = '%s/%s' % (kind, f[:-4])
    if twins:
        lines = '\n'.join('  %s is byte-identical to %s' % (a, b) for a, b in twins)
        raise SystemExit('TWO TILES BAKED TO THE SAME PICTURE:\n%s\n'
                         'Two names for one image means one of them is a lie on the map. '
                         'Give each its own cell.' % lines)


if __name__ == '__main__':
    main()

