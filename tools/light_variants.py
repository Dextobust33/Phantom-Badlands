"""Simulate lighting treatments on one rendered dungeon floor, so a LOOK can be chosen.

Deliberately post-processing rather than shader work: the point is to pick a treatment, and
writing the shader first would mean writing five of them and throwing four away.

Everything here is what a canvas_item shader would do per fragment - a radial falloff from the
player, optional extra falloffs from light sources, a scanline modulation - just evaluated on the
CPU at tile resolution instead.
"""
import io
import json
import math

from PIL import Image, ImageDraw

D = 'claude_screenshots/light'
meta = json.load(open(D + '/light_meta.json'))
base = Image.open(D + '/light_base.png').convert('RGB')
CELL = meta['cell']
PX, PY = meta['player']
LAMPS = [tuple(l) for l in meta['lamps']]
W, H = base.size


def lit(px, py, radius, floor_dark, lamps=(), lamp_radius=2.6, lamp_strength=0.85):
    """A brightness map in CELL space, expanded to pixels."""
    out = base.copy()
    src = base.load()
    dst = out.load()
    cx = (px + 0.5) * CELL
    cy = (py + 0.5) * CELL
    lps = [((lx + 0.5) * CELL, (ly + 0.5) * CELL) for lx, ly in lamps]
    R = radius * CELL
    LR = lamp_radius * CELL
    for y in range(H):
        for x in range(W):
            d = math.hypot(x - cx, y - cy)
            # smoothstep from full light to floor_dark
            t = min(1.0, max(0.0, (d - R * 0.45) / (R * 0.85)))
            t = t * t * (3 - 2 * t)
            b = 1.0 - t * (1.0 - floor_dark)
            for lx, ly in lps:
                dl = math.hypot(x - lx, y - ly)
                tl = min(1.0, max(0.0, (dl - LR * 0.25) / (LR * 0.9)))
                tl = tl * tl * (3 - 2 * tl)
                b = max(b, (1.0 - tl) * lamp_strength + floor_dark * tl)
            r, g, bl = src[x, y]
            dst[x, y] = (int(r * b), int(g * b), int(bl * b))
    return out


def scanlines(img, strength=0.28, period=4):
    out = img.copy()
    d = out.load()
    for y in range(H):
        if (y // (period // 2)) % 2 == 0:
            continue
        for x in range(W):
            r, g, b = d[x, y]
            d[x, y] = (int(r * (1 - strength)), int(g * (1 - strength)), int(b * (1 - strength)))
    return out


VARIANTS = [
    ('none  (what ships today)', base),
    ('torch, soft   radius 5.5, floor 45%', lit(PX, PY, 5.5, 0.45)),
    ('torch, tight  radius 3.5, floor 25%', lit(PX, PY, 3.5, 0.25)),
    ('torch + LAMPS  tight, lamps light their own patch', lit(PX, PY, 3.5, 0.25, LAMPS)),
    ('CRT scanlines (no torch), for comparison', scanlines(base)),
]

HEAD = 26
out = Image.new('RGB', (W, (H + HEAD) * len(VARIANTS) + 8), (18, 18, 20))
dr = ImageDraw.Draw(out)
y = 4
for label, im in VARIANTS:
    dr.text((8, y + 7), label, fill=(235, 235, 245))
    out.paste(im, (0, y + HEAD))
    y += H + HEAD
# mark the player so the falloff centre is legible
out.save('claude_screenshots/light_variants.png')
print('claude_screenshots/light_variants.png %s  player=%s lamps=%d' % (out.size, (PX, PY), len(LAMPS)))
