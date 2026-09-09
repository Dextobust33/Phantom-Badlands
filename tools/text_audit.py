"""Find player-facing descriptions whose numbers do not match the effect they describe.

Four such defects were found by hand on 2026-09-05 - the Character Stats page naming stats that
do nothing, card upgrades showing no upgrade, the extra-turn affix not saying what it does, and
the class picker still advertising a retired passive with numbers that were wrong even for it.
That is a pattern rather than a run of one-offs, so this checks it mechanically.

Where a record carries BOTH a `desc` string and an `effect` dict, every magnitude in the prose
should appear among the effect values. Flags the ones that do not.

Usage: python tools/text_audit.py
"""
import io
import os
import re

DESC_RE = re.compile(r'"desc"\s*:\s*"((?:[^"\\]|\\.)*)"')
EFFECT_RE = re.compile(r'"effect"\s*:\s*\{([^}]*)\}')
PCT_RE = re.compile(r'(?<![\w.])(\d+(?:\.\d+)?)\s*%')
PLUS_RE = re.compile(r'\+(\d+(?:\.\d+)?)(?![\d%])')
NUM_RE = re.compile(r':\s*(-?\d+(?:\.\d+)?)')


def records(path):
    """Yield (line_no, desc, effect_text) for records carrying both."""
    for i, line in enumerate(io.open(path, encoding='utf-8').read().split('\n'), 1):
        if '"desc"' not in line or '"effect"' not in line:
            continue
        d = DESC_RE.search(line)
        e = EFFECT_RE.search(line)
        if d and e:
            yield i, d.group(1), e.group(1)


def prose_numbers(text):
    """Magnitudes a player reads: percentages and explicit +N bonuses."""
    return [float(x) for x in PCT_RE.findall(text)] + [float(x) for x in PLUS_RE.findall(text)]


def effect_numbers(text):
    """Effect values, plus the x100 and /100 forms, since some are stored as fractions."""
    out = []
    for m in NUM_RE.finditer(text):
        v = abs(float(m.group(1)))
        out += [v, v * 100.0, v / 100.0]
    return out



# --- retired mechanics that prose still advertises -------------------------------------------
#
# 2026-09-09. The dungeon STEP BUDGET was retired (C2 - wandering monsters are the pressure now),
# but 13 theme tiles still told the player a crossing "costs +1 step" and 13 server messages said
# the same on arrival. Owner: "There are also some legacy effects that don't do anything anymore
# like extra steps." The counter those tiles feed is alive - it is the wandering-monster
# escalation clock - so the EFFECT is real and only the WORDING was legacy, which is the harder
# version of this bug to spot: nothing is broken, the player is just told a rule that no longer
# exists.
#
# Player-facing strings only. Code comments may still describe the old budget as history.
RETIRED_PROSE = [
    (r'\+\s*\d+\s+steps?', 'the step BUDGET is retired; say what it costs now (time -> '
                             'wandering monsters arrive sooner)'),
    (r'[Cc]osts?\s*\+\s*\d+\s+steps?', 'the step BUDGET is retired'),
]


def scan_retired(paths):
    """Flag player-facing prose that still describes a retired mechanic."""
    import re as _re
    n = 0
    for path in paths:
        if not os.path.exists(path):
            continue
        with io.open(path, encoding='utf-8') as fh:
            for i, line in enumerate(fh, 1):
                stripped = line.lstrip()
                if stripped.startswith('#'):
                    continue          # a comment may describe history
                if '"' not in line:
                    continue
                for pat, why in RETIRED_PROSE:
                    for m in _re.finditer(pat, line):
                        # only inside a string literal
                        before = line[:m.start()]
                        if before.count('"') % 2 == 0:
                            continue
                        print('  %s:%d  %s  -- %s' % (path, i, m.group(0).strip(), why))
                        n += 1
                        break
    return n


def main():
    total = 0
    flagged = 0
    for path in ('shared/path_database.gd', 'shared/card_upgrades.gd'):
        if not os.path.exists(path):
            continue
        print('=== %s ===' % path)
        hits = 0
        for ln, desc, eff in records(path):
            total += 1
            want = prose_numbers(desc)
            if not want:
                continue
            have = effect_numbers(eff)
            missing = [n for n in want if not any(abs(n - h) < 0.01 for h in have)]
            if missing:
                flagged += 1
                hits += 1
                short = desc if len(desc) < 100 else desc[:97] + '...'
                print('  L%-5d %s not in effect {%s}' % (ln, missing, eff.strip()[:66]))
                print('         "%s"' % short)
        if hits == 0:
            print('  (clean)')
        print('')
    print('=== retired mechanics still in player-facing prose ===')
    r = scan_retired(['client/client.gd', 'server/server.gd', 'shared/dungeon_database.gd'])
    if r == 0:
        print('  (clean)')
    print('')
    print('checked %d described effects, flagged %d; retired-prose hits %d' % (total, flagged, r))


if __name__ == '__main__':
    main()
