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
    print('checked %d described effects, flagged %d' % (total, flagged))


if __name__ == '__main__':
    main()
