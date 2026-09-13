"""Does anything STANDING ON a dungeon floor still read?

Owner 2026-09-13, art audit scope: overworld terrain tiles and dungeon floor art.

The floors were already chosen by eye in an earlier pass, so "is this floor pretty" is answered.
The question that is NOT answered, and the one that costs a player something, is whether the
things drawn ON a floor survive it. A busy, high-contrast floor can swallow a monster or a prop -
and that is measurable: composite each prop onto each floor and ask how much the composite
differs from the bare floor. If the answer is "barely", the prop is invisible there.

Also checks the floors against each other, because the point of nine packs is that one room
should not look like the last one.

USAGE
    python tools/dungeon_floor_audit.py
"""
import os

from PIL import Image

FLOORS = 'client/sprites/room_floor32'
PROPS = 'client/sprites/prop_floor32'
MONSTERS = 'client/sprites/monster_floor32'


# The colour the props' baked corridor floor is, byte-exact, matching DungeonTiles.FLOOR_COLOR.
FLOOR_COLOR = (82, 75, 36)


def over_prop(prop, floor):
    """What the GAME actually draws: the prop with its baked corridor floor replaced by the room
    floor, found by flood fill from the tile's edge.

    ⚑ THIS IS HERE BECAUSE THE FIRST VERSION OF THIS AUDIT WAS WRONG, and confidently so. It
    alpha-composited the prop onto the floor - which does NOTHING, because every prop is 100%
    opaque with the corridor floor baked in - and so reported that every room draws an olive
    square wherever a prop falls. That would have been a serious bug. It is not one: the renderer
    calls `DungeonComposite.over_prop`, which swaps that baked floor out, and the code even
    carries a comment about the four places this was fixed.

    A measurement that does not perform the same operation the game performs is measuring a
    different game. Check the instrument before reporting the fault."""
    w, h = prop.size
    px = prop.convert('RGB').load()
    is_floor = [[px[x, y] == FLOOR_COLOR for x in range(w)] for y in range(h)]
    seen = [[False] * w for _ in range(h)]
    stack = []
    for x in range(w):
        for y in (0, h - 1):
            if is_floor[y][x] and not seen[y][x]:
                seen[y][x] = True
                stack.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if is_floor[y][x] and not seen[y][x]:
                seen[y][x] = True
                stack.append((x, y))
    while stack:
        x, y = stack.pop()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and is_floor[ny][nx] and not seen[ny][nx]:
                seen[ny][nx] = True
                stack.append((nx, ny))
    out = prop.convert('RGBA').copy()
    fl = floor.convert('RGBA').load()
    op = out.load()
    for y in range(h):
        for x in range(w):
            if seen[y][x]:
                op[x, y] = fl[x, y]
    return out


def load_dir(d, limit=None):
    out = {}
    if not os.path.isdir(d):
        return out
    for f in sorted(os.listdir(d)):
        if not f.endswith('.png'):
            continue
        out[f[:-4]] = Image.open(os.path.join(d, f)).convert('RGBA')
        if limit and len(out) >= limit:
            break
    return out


def diff(a, b):
    """Mean difference over the WHOLE tile - right for comparing two floors."""
    pa, pb = a.load(), b.load()
    w, h = a.size
    t = 0.0
    for y in range(h):
        for x in range(w):
            r1, g1, b1 = pa[x, y][:3]
            r2, g2, b2 = pb[x, y][:3]
            t += (abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2)) / 3.0
    return t / (w * h)


def stands_out(floor_rgb, comp_rgb):
    """How well a thing reads against the floor it stands on, and how much of the tile it takes.

    ⚑ MEASURED OVER THE PIXELS THE THING ACTUALLY COVERS. The first version of this averaged
    over the whole 32x32 tile and reported `corridor_00 + prop_06` as low contrast at 6.3 - but
    prop_06 is two dark rocks covering a fifth of the tile, and looking at it at 8x they read
    perfectly well. Averaging a strong local contrast over a large unchanged area produces a
    small number and says nothing about visibility. The right unit is the contrast WHERE THE
    THING IS."""
    pa, pb = floor_rgb.load(), comp_rgb.load()
    w, h = floor_rgb.size
    tot = 0.0
    n = 0
    for y in range(h):
        for x in range(w):
            r1, g1, b1 = pa[x, y][:3]
            r2, g2, b2 = pb[x, y][:3]
            d = (abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2)) / 3.0
            if d > 2.0:
                tot += d
                n += 1
    if n == 0:
        return 0.0, 0.0       # draws nothing at all
    return tot / n, float(n) / (w * h)


def busyness(im):
    """How much the floor varies within itself. A calm floor lets a prop read; a noisy one
    competes with it."""
    px = im.convert('RGB').load()
    w, h = im.size
    tot = 0.0
    n = 0
    for y in range(h - 1):
        for x in range(w - 1):
            r, g, b = px[x, y]
            r2, g2, b2 = px[x + 1, y]
            r3, g3, b3 = px[x, y + 1]
            tot += (abs(r - r2) + abs(g - g2) + abs(b - b2)
                    + abs(r - r3) + abs(g - g3) + abs(b - b3)) / 6.0
            n += 1
    return tot / max(1, n)


def main():
    floors = {k: v for k, v in load_dir(FLOORS).items() if not k.startswith('_')}
    props = load_dir(PROPS, limit=8)
    mobs = load_dir(MONSTERS, limit=6)
    things = dict(props)
    things.update(mobs)
    print("%d floors, %d things drawn on them\n" % (len(floors), len(things)))

    print("=== IS THE FLOOR SO BUSY IT HIDES WHAT STANDS ON IT? ===")
    print("%-22s %-9s %-9s %s" % ("floor", "busyness", "contrast", "hardest thing to see on it"))
    rows = []
    for fname, floor in sorted(floors.items()):
        base = floor.convert('RGB')
        worst, worst_name, worst_cov = 1e9, '', 0.0
        for tname, thing in things.items():
            # Exactly what the renderer does, not a plausible-looking substitute.
            comp = over_prop(thing, floor)
            contrast, cov = stands_out(base, comp.convert('RGB'))
            # A thing that covers almost nothing is a different fault (an empty sprite), and is
            # reported by coverage rather than by contrast.
            if cov < 0.02:
                worst, worst_name, worst_cov = 0.0, tname + " (COVERS NOTHING)", cov
                break
            if contrast < worst:
                worst, worst_name, worst_cov = contrast, tname, cov
        rows.append((worst, fname, busyness(floor), "%s  [%.0f%% of the tile]" % (worst_name, worst_cov * 100)))
    rows.sort()
    for worst, fname, busy, wname in rows:
        flag = "  <-- LOW CONTRAST" if worst < 24.0 else ""
        print("%-22s %-9.1f %-9.1f %s%s" % (fname, busy, worst, wname, flag))

    print("\n=== DO THE ROOMS LOOK LIKE DIFFERENT ROOMS? ===")
    keys = sorted(floors)
    pairs = []
    for i in range(len(keys)):
        for j in range(i + 1, len(keys)):
            # ⚑ VARIANTS OF ONE PACK ARE MEANT TO LOOK ALIKE. The first run flagged all six
            # shroom_chasm pairs as "the same room twice" - they are `shroom_chasm_00..03`,
            # deliberate variety WITHIN one room type, and resembling each other is the job.
            # Comparing them was the wrong question, not a finding.
            if keys[i].rsplit('_', 1)[0] == keys[j].rsplit('_', 1)[0]:
                continue
            pairs.append((diff(floors[keys[i]].convert('RGB'), floors[keys[j]].convert('RGB')),
                          keys[i], keys[j]))
    pairs.sort()
    for d, a, b in pairs[:6]:
        flag = "  <-- SAME ROOM TWICE" if d < 12.0 else ""
        print("  %-6.1f %-24s %-24s%s" % (d, a, b, flag))


if __name__ == '__main__':
    main()
