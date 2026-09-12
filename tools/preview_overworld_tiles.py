"""Compose the baked overworld tiles into a sample map, so the look can be judged before more
art is cut.

Phase 2.95 PHASE 2. The renderer will compose the whole 23x23 grid into ONE image (the pattern
`client/sanctuary_room.gd` uses) with a biome ground underneath and a transparent prop over it.
This does exactly that, offline, so the pairing of ground and prop can be checked by eye at the
size a player will see - which is the only way to tell whether a tile reads.

USAGE
    python tools/preview_overworld_tiles.py
"""
import os

from PIL import Image, ImageDraw, ImageFont

SRC = 'client/sprites/overworld32'
OUT = 'claude_screenshots/overworld_tiles_preview.png'
TILE = 32
SCALE = 2
PAD = 26

# A strip per biome, showing the ground alone and then each prop laid over it.
# All fourteen gatherables the owner asked for, then the land itself. `empty` is absent: it IS
# the ground, and a prop on it would hide the thing it is meant to be.
PROPS = ['tree', 'stone', 'ore_vein', 'dense_brush', 'bush', 'herb', 'flower', 'reed',
         'brambleberry', 'mountain_herb', 'mushroom', 'swamp_lily', 'cactus', 'ice_bloom',
         'water', 'deep_water', 'path', 'floor', 'bridge', 'wall']
BIOMES = ['plains', 'forest', 'mountain', 'swamp', 'snow', 'desert']


def load(path):
    return Image.open(path).convert('RGBA') if os.path.exists(path) else None


def main():
    try:
        font = ImageFont.truetype(r'C:\Windows\Fonts\consola.ttf', 12)
        small = ImageFont.truetype(r'C:\Windows\Fonts\consola.ttf', 10)
    except OSError:
        font = small = ImageFont.load_default()

    cell = TILE * SCALE
    w = 120 + (len(PROPS) + 1) * (cell + 4)
    h = PAD + len(BIOMES) * (cell + PAD)
    out = Image.new('RGBA', (w, h), (20, 20, 24, 255))
    d = ImageDraw.Draw(out)

    for i, name in enumerate(['ground'] + PROPS):
        d.text((120 + i * (cell + 4), 6), name[:9], font=small, fill=(190, 190, 130, 255))

    for r, biome in enumerate(BIOMES):
        y = PAD + r * (cell + PAD)
        d.text((6, y + cell // 2 - 6), biome, font=font, fill=(220, 220, 220, 255))
        ground = load(os.path.join(SRC, 'ground', biome + '.png'))
        if ground is None:
            continue
        ground = ground.resize((cell, cell), Image.NEAREST)
        out.alpha_composite(ground, (120, y))
        for i, prop in enumerate(PROPS):
            p = load(os.path.join(SRC, 'tile', prop + '.png'))
            x = 120 + (i + 1) * (cell + 4)
            out.alpha_composite(ground, (x, y))
            if p is not None:
                out.alpha_composite(p.resize((cell, cell), Image.NEAREST), (x, y))

    # And a patch of map: ground with scattered props, at the size a player actually sees.
    os.makedirs('claude_screenshots', exist_ok=True)
    out.save(OUT)
    print('wrote %s (%dx%d)' % (OUT, w, h))

    # a second image: a 16x10 field of forest with props sprinkled, 1:1 and 2x
    field_w, field_h = 16, 10
    ground = load(os.path.join(SRC, 'ground', 'forest.png'))
    scatter = {(2, 1): 'tree', (5, 2): 'tree', (9, 1): 'stone', (12, 3): 'bush',
               (3, 5): 'herb', (7, 6): 'flower', (11, 7): 'reed', (14, 5): 'tree',
               (1, 8): 'dense_brush', (6, 8): 'stone', (13, 1): 'brambleberry',
               (4, 3): 'mountain_herb', (8, 4): 'tree', (10, 5): 'bush'}
    field = Image.new('RGBA', (field_w * TILE, field_h * TILE), (0, 0, 0, 255))
    for yy in range(field_h):
        for xx in range(field_w):
            field.alpha_composite(ground, (xx * TILE, yy * TILE))
    for (xx, yy), prop in scatter.items():
        p = load(os.path.join(SRC, 'tile', prop + '.png'))
        if p is not None:
            field.alpha_composite(p, (xx * TILE, yy * TILE))
    big = field.resize((field_w * TILE * 2, field_h * TILE * 2), Image.NEAREST)
    big.save('claude_screenshots/overworld_field_preview.png')
    print('wrote claude_screenshots/overworld_field_preview.png')


if __name__ == '__main__':
    main()
