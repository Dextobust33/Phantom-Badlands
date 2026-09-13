"""Which overworld tiles can a player NOT tell apart?

Owner 2026-09-13: *"For art show me alternatives for each and I can choose the better one. We may
want to do this for more than just gatherables if there may be other subpar art that made it
through."*

WHY THIS AND NOT A CONTACT SHEET. The gatherable audit found its faults by eye, and the faults it
found were all ONE thing: `tree`, `bush`, `dense_brush`, `reed` and `mountain_herb` were cut from
the same pack, so they were all the same green - tree against bush being the worst, two different
JOBS with near-identical art. That is not a question about whether a tile is pretty. It is a
question about whether two tiles are DISTINGUISHABLE, which is measurable, and measuring it turns
67 tiles into a short list worth looking at.

So each tile is composed exactly the way the game composes it - blended onto the biome ground it
actually stands on - then scaled to the 26 pixels the grid really draws, which is where detail
dies. Pairs are compared on that.

USAGE
    python tools/tile_confusion_audit.py              # the report
    python tools/tile_confusion_audit.py --sheet      # plus a contact sheet of the worst pairs
"""
import os
import sys

from PIL import Image

SRC = 'client/sprites/overworld32'
PLAY_PX = 26          # client.gd OVERWORLD_SPRITE_PX - the size that actually reaches the eye
OUT_DIR = 'claude_screenshots'

# What ground each tile really stands on, so nothing is judged against a background it never has.
GROUND_FOR = {
    'reed': 'swamp', 'swamp_lily': 'swamp', 'mushroom': 'swamp',
    'cactus': 'desert', 'ice_bloom': 'snow', 'mountain_herb': 'mountain',
    'stone': 'mountain', 'ore_vein': 'mountain',
    'tree': 'forest', 'dense_brush': 'forest', 'brambleberry': 'forest',
}
DEFAULT_GROUND = 'plains'

# Tiles whose JOBS are different enough that looking alike is a real fault. Everything is
# compared, but a collision inside one of these groups is what actually costs a player something.
JOB_GROUPS = {
    'gatherable': ['tree', 'bush', 'dense_brush', 'herb', 'flower', 'reed', 'brambleberry',
                   'mountain_herb', 'mushroom', 'swamp_lily', 'cactus', 'ice_bloom',
                   'stone', 'ore_vein'],
    'walkable': ['path', 'floor', 'bridge', 'water', 'deep_water'],
    'station': ['forge', 'apothecary', 'workbench', 'enchant_table', 'market', 'inn',
                'blacksmith', 'healer', 'companion_stable', 'cartographer', 'quest_board'],
}


def load(path):
    if not os.path.exists(path):
        return None
    return Image.open(path).convert('RGBA')


def compose(tile_name):
    """A tile as the player sees it: on its real ground, at the real drawn size."""
    ground = load('%s/ground/%s.png' % (SRC, GROUND_FOR.get(tile_name, DEFAULT_GROUND)))
    if ground is None:
        ground = load('%s/ground/plains.png' % SRC)
    if ground is None:
        return None
    base = ground.copy()
    tile = load('%s/tile/%s.png' % (SRC, tile_name))
    if tile is None:
        return None
    base.alpha_composite(tile)
    return base.convert('RGB').resize((PLAY_PX, PLAY_PX), Image.LANCZOS)


def distance(a, b):
    """Mean per-pixel colour distance, 0 = identical. Luma-weighted, because the eye separates
    brightness far better than hue and two tiles of the same brightness read as the same thing."""
    pa, pb = a.load(), b.load()
    total = 0.0
    n = 0
    for y in range(PLAY_PX):
        for x in range(PLAY_PX):
            r1, g1, b1 = pa[x, y]
            r2, g2, b2 = pb[x, y]
            # Rec. 601 luma plus a softer colour term.
            l1 = 0.299 * r1 + 0.587 * g1 + 0.114 * b1
            l2 = 0.299 * r2 + 0.587 * g2 + 0.114 * b2
            total += abs(l1 - l2) + 0.25 * (abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2)) / 3.0
            n += 1
    return total / max(1, n)


def main():
    names = sorted(f[:-4] for f in os.listdir('%s/tile' % SRC) if f.endswith('.png'))
    composed = {}
    for n in names:
        im = compose(n)
        if im is not None:
            composed[n] = im
    print("composed %d tiles at %dpx, each on the ground it really stands on\n" % (
        len(composed), PLAY_PX))

    job_of = {}
    for job, members in JOB_GROUPS.items():
        for m in members:
            job_of[m] = job

    pairs = []
    keys = sorted(composed)
    for i in range(len(keys)):
        for j in range(i + 1, len(keys)):
            a, b = keys[i], keys[j]
            d = distance(composed[a], composed[b])
            same_job = job_of.get(a) is not None and job_of.get(a) == job_of.get(b)
            pairs.append((d, a, b, same_job))
    pairs.sort()

    print("=== THE TILES A PLAYER CANNOT TELL APART ===")
    print("%-7s %-18s %-18s %s" % ("dist", "tile", "tile", "same job?"))
    shown = 0
    worst = []
    for d, a, b, same_job in pairs:
        if d > 18.0 and shown >= 12:
            break
        if shown >= 25:
            break
        print("%-7.2f %-18s %-18s %s" % (d, a, b, "<-- SAME JOB" if same_job else ""))
        worst.append((d, a, b))
        shown += 1

    print("\n=== BY JOB: the collisions that actually cost a player something ===")
    for job, members in JOB_GROUPS.items():
        inside = [(d, a, b) for d, a, b, sj in pairs if sj and job_of.get(a) == job]
        inside.sort()
        if not inside:
            continue
        print("\n  %s:" % job)
        for d, a, b in inside[:6]:
            flag = "  <-- TOO CLOSE" if d < 18.0 else ""
            print("    %-6.2f %-18s vs %-18s%s" % (d, a, b, flag))

    if '--sheet' in sys.argv:
        _sheet(composed, worst)


def _sheet(composed, worst):
    """A contact sheet of the closest pairs, at play size and at 6x, so the eye can confirm."""
    if not worst:
        return
    from PIL import ImageDraw
    rows = len(worst)
    cell = PLAY_PX * 6
    W = cell * 2 + 300
    H = rows * (cell + 12) + 40
    sheet = Image.new('RGB', (W, H), (18, 20, 24))
    d = ImageDraw.Draw(sheet)
    d.text((10, 10), "Closest tile pairs, composed on their real ground, shown at 6x", fill=(230, 230, 230))
    y = 34
    for dist, a, b in worst:
        for k, name in enumerate((a, b)):
            im = composed[name].resize((cell, cell), Image.NEAREST)
            sheet.paste(im, (k * cell + 4, y))
        d.text((cell * 2 + 14, y + cell // 2 - 14), "%s" % a, fill=(240, 220, 140))
        d.text((cell * 2 + 14, y + cell // 2), "%s" % b, fill=(240, 220, 140))
        d.text((cell * 2 + 14, y + cell // 2 + 14), "distance %.1f" % dist, fill=(160, 160, 160))
        y += cell + 12
    out = os.path.join(OUT_DIR, 'tile_confusion_pairs.png')
    sheet.save(out)
    print("\nwrote %s (%dx%d)" % (out, W, H))


if __name__ == '__main__':
    main()
