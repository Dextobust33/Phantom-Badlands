"""Re-bake glyph floor tiles for characters the ORIGINAL bake font could not draw.

WHY THIS EXISTS. `client/sprites/glyph_floor32` renders each (character, colour) pair onto the
dungeon floor tile so a glyph is an image like every other cell. It was baked in Consolas -- and
Consolas has no U+25C6, U+25C9 or U+2726, so for those the baker faithfully rendered the font's
MISSING-GLYPH BOX and baked a little "[?]" onto the floor. Six characters were affected.

Owner 2026-09-10 saw one of them and reported "Elite monsters don't have a sprite": the Elite Den
marker is U+25C6, and what was on screen was a magenta tofu box. Measuring the screenshot is what
identified it -- a 31x43 rectangle outline is not any glyph this game draws on purpose.

THE RULE THIS ENFORCES: never bake a character the font cannot draw. Coverage is asserted by
rendering a private-use codepoint (guaranteed absent) and comparing -- if the character renders
the same as that, the font is drawing .notdef and the bake is refused. `verify_dungeon_art.gd`
carries the matching ship-time gate: two different characters with pixel-identical art are both
tofu, and that fails the build.

USAGE
    python tools/bake_glyph_tiles.py           # re-bake the affected characters, all colours
"""
import glob
import os
import re

from PIL import Image, ImageDraw, ImageFont

OUT = 'client/sprites/glyph_floor32'
FLOOR = (82, 75, 36, 255)          # measured off the existing tiles
TILE = 32
NOTDEF = '\ue123'                  # private use -- no font has it, so it renders .notdef

# Segoe UI Symbol, checked below rather than trusted: it is the only font on this machine that
# carries all six of these AND draws them distinctly.
FONT_PATH = r'C:\Windows\Fonts\seguisym.ttf'

# Exactly the characters the original bake got wrong. Everything else keeps its Consolas tile.
BROKEN = ['\u25aa', '\u25b2', '\u25c6', '\u25c9', '\u2666', '\u2726']

TARGET_H = 18                      # px of ink, matching the letters already baked (y7..y24)


def render_mask(font, ch, box=64):
    im = Image.new('L', (box, box), 0)
    ImageDraw.Draw(im).text((box // 2, box // 2), ch, font=font, fill=255, anchor='mm')
    return im


def assert_covered(path, chars):
    """Refuse to bake anything this font renders as .notdef. This is the whole point."""
    probe = ImageFont.truetype(path, 32)
    ref = render_mask(probe, NOTDEF).tobytes()
    missing = [hex(ord(c)) for c in chars if render_mask(probe, c).tobytes() == ref]
    if missing:
        raise SystemExit('%s cannot draw %s - baking would produce the missing-glyph box, '
                         'which is the exact bug this script exists to undo'
                         % (os.path.basename(path), ', '.join(missing)))
    shapes = {}
    for c in chars:
        k = render_mask(probe, c).tobytes()
        if k in shapes:
            raise SystemExit('%s draws U+%04X and U+%04X identically - they would be '
                             'indistinguishable on the floor' % (os.path.basename(path), ord(c), ord(shapes[k])))
        shapes[k] = c


def bake(ch, hexcol, dest):
    col = tuple(int(hexcol[i:i + 2], 16) for i in (0, 2, 4))
    # size the font so the INK is TARGET_H tall, so a symbol matches the letters beside it
    size = 24
    for _ in range(12):
        f = ImageFont.truetype(FONT_PATH, size)
        bb = render_mask(f, ch).getbbox()
        h = bb[3] - bb[1]
        if h == 0:
            raise SystemExit('U+%04X rendered nothing at size %d' % (ord(ch), size))
        if abs(h - TARGET_H) <= 1:
            break
        size = max(6, int(round(size * TARGET_H / h)))
    f = ImageFont.truetype(FONT_PATH, size)

    glyph = Image.new('RGBA', (TILE, TILE), (0, 0, 0, 0))
    d = ImageDraw.Draw(glyph)
    # the drop shadow the existing tiles have - it is what makes a glyph read against the floor
    d.text((TILE // 2 + 1, TILE // 2 + 1), ch, font=f, fill=(0, 0, 0, 255), anchor='mm')
    d.text((TILE // 2, TILE // 2), ch, font=f, fill=col + (255,), anchor='mm')

    out = Image.new('RGBA', (TILE, TILE), FLOOR)
    out.alpha_composite(glyph)
    out.save(dest)
    return size


if __name__ == '__main__':
    assert_covered(FONT_PATH, BROKEN)
    print('font check: %s draws all %d characters, distinctly' % (os.path.basename(FONT_PATH), len(BROKEN)))
    n = 0
    for ch in BROKEN:
        cp = 'u%04x' % ord(ch)
        hits = sorted(glob.glob(os.path.join(OUT, cp + '_*.png')))
        if not hits:
            print('  U+%04X - no tiles on disk, skipped' % ord(ch))
            continue
        for h in hits:
            hexcol = re.search(r'_([0-9A-Fa-f]{6})\.png$', h).group(1)
            size = bake(ch, hexcol, h)
            n += 1
        print('  U+%04X re-baked %d colours (font size %d)' % (ord(ch), len(hits), size))
    print('\n%d tiles re-baked. Run tools/verify_dungeon_art.gd to confirm none are tofu.' % n)
