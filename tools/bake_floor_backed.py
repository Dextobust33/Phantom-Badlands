"""Bake a transparent sprite onto the dungeon floor tile, at the 32px every dungeon cell uses.

WHY THIS EXISTS. Every dungeon sprite carries the floor baked into it, because BBCode cannot
layer two images in one cell. Those bakes were originally produced by ad-hoc scripts that were
never committed and are gone -- so `prop_floor32`, `tile_floor32`, `free_floor32` and
`egg_floor32` are currently irreplaceable DATA when they should be reproducible OUTPUT (see
docs/BACKLOG.md, "Write the BAKE GENERATORS as committed tools"). This is the first of them,
written when `loot_floor32` turned out to be missing the `consumable` kind and the alternative
was another uncommitted one-liner.

USAGE
    python tools/bake_floor_backed.py <source.png> <out_dir> <name>

    python tools/bake_floor_backed.py \
        client/sprites/items_pack/Consume/Potion/LargePotionYellow.png \
        client/sprites/loot_floor32 consumable

The source may be any size; it is scaled to fit the tile with NEAREST (pixel art at a fractional
or smoothed scale is mush) and centred. The floor comes from the darkcave sheet cell the game
itself uses, read from client/dungeon_tiles.gd rather than hardcoded here, so this cannot drift
away from what the renderer draws.
"""
import os
import re
import sys

from PIL import Image

TILE = 32
TILES_GD = 'client/dungeon_tiles.gd'


def floor_tile():
    """The floor cell the game uses, resolved from the source of truth rather than copied."""
    src = open(TILES_GD, encoding='utf-8').read()
    sheet = re.search(r'const SHEET_CAVE16 := "([^"]+)"', src).group(1)
    cx, cy = re.search(r'const CAVE_FLOOR := Vector2i\((\d+), (\d+)\)', src).groups()
    path = sheet.replace('res://', '')
    im = Image.open(path).convert('RGBA')
    cell = im.crop((int(cx) * 16, int(cy) * 16, (int(cx) + 1) * 16, (int(cy) + 1) * 16))
    return cell.resize((TILE, TILE), Image.NEAREST)


def bake(src_path, out_dir, name):
    floor = floor_tile()
    spr = Image.open(src_path).convert('RGBA')

    # Scale to fit INSIDE the tile, preserving aspect, on a whole-number factor where possible so
    # the pixel grid survives. A sprite drawn at 1.4x looks soft next to tiles drawn at 2x.
    w, h = spr.size
    scale = min(TILE / w, TILE / h)
    whole = max(1, int(scale))
    if abs(scale - whole) < 0.01 or whole >= 1 and w * whole <= TILE and h * whole <= TILE:
        scale = whole
    nw, nh = max(1, int(w * scale)), max(1, int(h * scale))
    spr = spr.resize((nw, nh), Image.NEAREST)

    out = floor.copy()
    out.alpha_composite(spr, ((TILE - nw) // 2, (TILE - nh) // 2))

    if out.getextrema()[3][0] != 255:
        raise SystemExit('bake is not fully opaque - a floor-backed tile must be')

    os.makedirs(out_dir, exist_ok=True)
    dest = os.path.join(out_dir, name + '.png')
    out.save(dest)
    print('baked %s  (source %dx%d scaled x%g, centred on the %s floor)'
          % (dest, w, h, scale, 'darkcave'))
    return dest


if __name__ == '__main__':
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    bake(sys.argv[1], sys.argv[2], sys.argv[3])
