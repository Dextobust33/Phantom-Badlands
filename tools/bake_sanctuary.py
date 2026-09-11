#!/usr/bin/env python3
"""Bake the Sanctuary's sprite pieces from the Raven Fantasy packs.

Phase 3.45 (sprite interiors), first slice: the Sanctuary, one interior end to end.

Every piece is cut at 16px scale and doubled with NEAREST, so it matches the dungeon's 32px cell
(a 16px tile at 2x) and the Raven packs' own 32px renders, which are the same art at 2x.

    python tools/bake_sanctuary.py

Coordinates were chosen by rendering each sheet with every object's alpha bounding box numbered
(connected components of visible pixels) and then LOOKING at a 4x contact sheet of the picks:
the 32px sheet is not a clean 32px grid - objects straddle cell boundaries on a 16px grid - so
reading cells off it by eye cut half of them in two.

LICENCE: the output is cut from packs that may not be redistributed (docs/ASSET_LICENCES.md).
It is gitignored and listed in tools/licensed_assets.manifest; this generator is our code and is
public, so the art can always be rebuilt from the purchased packs.
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RAVEN = os.path.join(ROOT, "client", "sprites", "raven")
OUT = os.path.join(ROOT, "client", "sprites", "sanctuary32")

INTERIORS = os.path.join(RAVEN, "interiors", "All Tileset", "16x16.png")
COZY = os.path.join(RAVEN, "cozy_home", "All Tileset", "Tileset.png")


def cell(cx, cy, w=1, h=1):
    """A rectangle in 16px CELLS."""
    return (cx * 16, cy * 16, (cx + w) * 16, (cy + h) * 16)


# name -> (sheet, (x0, y0, x1, y1) in source pixels). Tiles are exactly one 16px cell, so they
# come out 32x32; objects keep their own size (x2) and the composer anchors them to a cell.
PIECES = {
    # --- tiles -------------------------------------------------------------------------------
    # The FLOOR is one cell, tiled. Measured by tiling every candidate across a patch: the centre
    # plank cell (14, 1) is the only one that tiles with NO seam - its boards run edge to edge.
    # (13, 1) carries a board end at its edge (vertical stripes every cell), and the 3x3 block
    # around it is a FRAMED panel (a dark grid every three cells). Both were screenshotted in-game.
    "floor": (INTERIORS, cell(14, 1)),
    "wall": (INTERIORS, cell(1, 6)),
    "window": (INTERIORS, cell(9, 3)),
    # --- objects -----------------------------------------------------------------------------
    "door": (INTERIORS, cell(2, 9, 1, 2)),          # the open door: it is the way OUT
    "chest": (COZY, (320, 352, 352, 384)),          # S - storage
    "statue": (INTERIORS, (332, 145, 356, 192)),    # U - upgrades
    "cushion": (COZY, (64, 193, 80, 206)),          # C - a companion's place
    "mirror": (COZY, (80, 150, 96, 176)),           # M - choose your Sanctuary look (arched glass)
    "cushion_teal": (COZY, (168, 257, 184, 272)),   # K - the Stable's cushion
    "rug_green": (COZY, (67, 210, 125, 254)),       # under the Stable
    "rug_blue": (COZY, (18, 195, 62, 253)),
    "firepit": (COZY, (299, 121, 325, 151)),
    "lamp": (COZY, (360, 168, 392, 208)),
    "shelf": (INTERIORS, (291, 98, 317, 140)),
    "barrel": (INTERIORS, (272, 232, 288, 256)),
    "crate": (INTERIORS, (229, 290, 251, 317)),
}


def main():
    for sheet in (INTERIORS, COZY):
        if not os.path.exists(sheet):
            print("MISSING source sheet: %s" % sheet)
            print("The Raven packs are licence-restricted and untracked; restore them from the")
            print("private art backup first (docs/ASSET_LICENCES.md).")
            return 1
    os.makedirs(OUT, exist_ok=True)
    cache = {}
    for name, (sheet, rect) in PIECES.items():
        if sheet not in cache:
            cache[sheet] = Image.open(sheet).convert("RGBA")
        piece = cache[sheet].crop(rect)
        if piece.getbbox() is None:
            print("REFUSING %s: the rectangle %s is empty" % (name, rect))
            return 1
        piece = piece.resize((piece.width * 2, piece.height * 2), Image.NEAREST)
        piece.save(os.path.join(OUT, name + ".png"))
        print("  %-13s %3dx%-3d" % (name, piece.width, piece.height))
    print("baked %d pieces -> %s" % (len(PIECES), OUT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
