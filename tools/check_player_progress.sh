#!/bin/bash
# Live player progression snapshot.
#
# Why this exists: high-level balance cannot be validated until players reach high levels, and
# they could not until the 2026-09-05 early-game pass. This reports how far the live population
# has actually climbed, so the balance work can be re-opened when there is real data behind it.
#
# 2026-09-05 — the report is split by ERA, on the owner's note: "there are a few legacy
# characters with high level gear that isn't easy to obtain with the current balancing." A
# character grown under the old rules is not evidence about the new ones, and letting one set
# the "highest level" line would re-open balance work against a number no current player could
# reach. Characters are dated by `created_at`; items generated from 2026-09-05 carry their own
# `created_at`, so gear can be dated independently of the character holding it (anything older
# is reported as undated rather than assumed current).
#
# Usage: bash tools/check_player_progress.sh
SSH_KEY="/c/Users/Dexto/Desktop/PhantomBadlandsSSH/ssh-key-2026-04-21.key"
SERVER="ubuntu@5.78.217.135"
DIR="/home/ubuntu/.local/share/godot/app_userdata/PhantomBadlands/data/characters"

# Unix time of the balance cutoff. Characters created before this grew under the old rules.
CUTOFF=$(date -d "2026-09-05 00:00:00 UTC" +%s 2>/dev/null || echo 1788480000)

ssh -i "$SSH_KEY" "$SERVER" "CUTOFF=$CUTOFF python3 - <<'PY'
import json, glob, collections, os, datetime

CUTOFF = int(os.environ.get('CUTOFF', '0'))
cur, legacy = [], []
gear_dated = gear_undated = 0
gear_legacy_high = []

for f in glob.glob('$DIR/*.json'):
    if f.endswith('.bak'):
        continue
    try:
        d = json.load(open(f))
    except Exception:
        continue
    if not d.get('class'):
        continue
    made = int(d.get('created_at', 0) or 0)
    row = (int(d.get('level', 1)), d.get('name'), d.get('class'), made)
    (cur if made >= CUTOFF else legacy).append(row)
    # Date the gear this character is actually wearing.
    for slot, it in (d.get('equipped') or {}).items():
        if not isinstance(it, dict) or not it:
            continue
        ts = int(it.get('created_at', 0) or 0)
        if ts:
            gear_dated += 1
        else:
            gear_undated += 1
            if int(it.get('level', 0)) >= 25:
                gear_legacy_high.append((int(it.get('level', 0)), d.get('name'), it.get('name')))

cur.sort(reverse=True); legacy.sort(reverse=True)

def show(title, rows):
    print('%s: %d' % (title, len(rows)))
    if not rows:
        return
    print('  %-6s %-18s %-10s %s' % ('level', 'name', 'class', 'created'))
    for lv, n, c, made in rows[:10]:
        when = datetime.datetime.fromtimestamp(made, datetime.timezone.utc).strftime('%Y-%m-%d') if made else 'undated'
        print('  %-6d %-18s %-10s %s' % (lv, n, c, when))
    print()

print()
show('CURRENT-ERA characters (created on/after the 2026-09-05 balance pass)', cur)
show('LEGACY characters (grown under the old rules - NOT evidence for balance)', legacy)

band = collections.Counter()
for lv, _, _, _ in cur:
    if lv < 10: band['  1-9  '] += 1
    elif lv < 25: band[' 10-24 '] += 1
    elif lv < 50: band[' 25-49 '] += 1
    elif lv < 100: band[' 50-99 '] += 1
    else: band['100+   '] += 1
print('current-era distribution:')
if not band:
    print('  (none yet)')
for k in ['  1-9  ', ' 10-24 ', ' 25-49 ', ' 50-99 ', '100+   ']:
    if band[k]:
        print('  %s %s (%d)' % (k, '#' * band[k], band[k]))

print()
print('equipped gear: %d dated (generated under current rules), %d undated (pre-2026-09-05)'
      % (gear_dated, gear_undated))
if gear_legacy_high:
    gear_legacy_high.sort(reverse=True)
    print('  high-level UNDATED gear - the legacy kit the owner flagged; do not read these')
    print('  as reachable under current drop rates:')
    for lv, who, iname in gear_legacy_high[:8]:
        print('    L%-4d %-16s %s' % (lv, who, iname))

top = cur[0][0] if cur else 0
ltop = legacy[0][0] if legacy else 0
print()
print('highest CURRENT-ERA level: %d   (highest legacy: %d)' % (top, ltop))
if top >= 50:
    print('>> ACTIONABLE: current-era characters past L50 exist. High-level balance can now be')
    print('   validated against real data instead of the lootsim extrapolation.')
elif top >= 25:
    print('>> Current-era characters past L25 exist - beyond the range grown characters could')
    print('   reach. Worth re-running calibrate to check make_char against them.')
else:
    print('>> Still inside the range already measured. Nothing to re-open yet.')
if ltop > top:
    print('   (A legacy character is higher, but it grew under the old rules - it is not a')
    print('    reason to re-open the balance work.)')
PY"
