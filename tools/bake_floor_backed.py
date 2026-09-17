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
    return bake_image(Image.open(src_path).convert('RGBA'), out_dir, name)


def bake_frame(sheet_path, frame, out_dir, name, cell=16):
    """Bake ONE frame out of a horizontal sprite strip.

    The mob packs ship animation as a single row (ChickenA.png is 144x16 = nine 16px frames), so
    a strip cannot be handed to `bake` directly - it would be scaled down to fit the whole row
    into one 32px tile and come out as a smear. Cropping here rather than writing nine temp PNGs
    keeps the bake reproducible from committed sources, which is the whole point of this file."""
    im = Image.open(sheet_path).convert('RGBA')
    x = frame * cell
    return bake_image(im.crop((x, 0, x + cell, im.size[1])), out_dir, name)


def bake_image(spr, out_dir, name):
    floor = floor_tile()

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


# The PER-ITEM floor-loot set, 2026-09-15. Committed as DATA rather than left in shell
# history, because the whole point of this file is that these bakes are reproducible output
# and not irreplaceable art (see the module docstring).
#
# WHY IT EXISTS. The dungeon floor used to pick its sprite from `kind`, which is a gameplay
# bucket - every helm, blade, ring and pair of boots is `equipment`, and equipment.png is a
# picture of a shield. Owner 2026-09-15: "most floor loot equipment looks like a shield, one
# of the scrolls looks like a potion." The keys below are the ones server.gd::_floor_loot_art
# produces, and tools/verify_dungeon_art.gd fails the release if one of them has no art.
#
# Sources are all `items_pack` (CC0 - docs/ASSET_LICENCES.md). The seven equipment pieces are
# deliberately one MATERIAL (the Steel family), so they read as a matched set that differs by
# SHAPE - which is the thing a player has to tell apart at 32 pixels on a dark floor.
LOOT_SOURCES = {
    'eq_weapon': 'Equip/Set/SteelBlade2.png',
    'eq_armor':  'Equip/Set/SteelChest.png',
    'eq_helm':   'Equip/Set/SteelHelm.png',
    'eq_shield': 'Equip/Set/SteelShield.png',
    'eq_boots':  'Equip/Feet/BootsA0.png',
    'eq_ring':   'Equip/Finger/RingA0.png',
    'eq_amulet': 'Equip/Neck/Neck0.png',
    'cn_potion': 'Consume/Potion/LargePotionRed.png',
    # ScrollSealed, not Scroll: the open scroll is a pale rectangle that fills the whole cell
    # and renders as a smear on a dark floor. Caught by looking at a contact sheet - no check
    # can tell you that a picture is unreadable.
    'cn_scroll': 'ScrollSealed.png',
    'cn_tome':   'Book/Book0.png',
    'cn_charm':  'Clover.png',
    'cn_gem':    'Gem.png',
    'cn_pouch':  'Sack0.png',
    'cn_stone':  'RuneStone/RuneStone0.png',
}
PACK = 'client/sprites/items_pack'
LOOT_OUT = 'client/sprites/loot_floor32'


# ── CRITTERS: the passive creatures that wander a dungeon floor ──────────────────────────────
#
# Owner 2026-09-17, asked how chickens should work: *"A creature you catch."* They are a FOOD
# source found inside a dungeon, for the rest that eats food - so they need the same floor-backed
# 32px treatment as every other dungeon entity, at the frame naming `dungeon_sprites.monster_path`
# expects (`<slug>_<frame>` plus an `_alert` twin).
#
# Frames 0-2 of ChickenA are the walk cycle (frames 3-5 are a second gait and 6-8 a peck; read off
# a contact sheet, because no check can tell you which nine frames are which). The ALERT twin is
# the SAME image on purpose: a chicken has no alert state, it flees. It is baked anyway so a
# renderer that asks for one can never hit a missing file - a failed `[img]` draws nothing at all
# and punches a hole in the floor.
CRITTER_SOURCES = {
    'chicken': ('client/sprites/mobs_pack/ChickenA.png', [0, 1, 2]),
}
MONSTER_OUT = 'client/sprites/monster_floor32'


def rebake_critters():
    n = 0
    for name, (sheet, frames) in sorted(CRITTER_SOURCES.items()):
        for i, fr in enumerate(frames):
            bake_frame(sheet, fr, MONSTER_OUT, '%s_%d' % (name, i))
            bake_frame(sheet, fr, MONSTER_OUT, '%s_%d_alert' % (name, i))
            n += 2
    print()
    print('%d critter tiles baked. Godot serves .godot/imported, so re-import then verify:' % n)
    print('    godot --headless --path . --import')
    print('    godot --headless --path . --script res://tools/verify_dungeon_art.gd')


def rebake_loot():
    for name, rel in sorted(LOOT_SOURCES.items()):
        bake(os.path.join(PACK, rel), LOOT_OUT, name)
    print()
    print('%d loot sprites re-baked. Godot serves .godot/imported, so a re-bake is invisible'
          % len(LOOT_SOURCES))
    print('until you import. Then verify:')
    print('    godot --headless --path . --import')
    print('    godot --headless --path . --script res://tools/verify_dungeon_art.gd')


if __name__ == '__main__':
    if len(sys.argv) == 2 and sys.argv[1] == '--rebake-loot':
        rebake_loot()
    elif len(sys.argv) == 2 and sys.argv[1] == '--rebake-critters':
        rebake_critters()
    elif len(sys.argv) == 4:
        bake(sys.argv[1], sys.argv[2], sys.argv[3])
    else:
        raise SystemExit(__doc__)
