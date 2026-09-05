#!/bin/bash
# Live player progression snapshot.
#
# Why this exists: high-level balance cannot be validated until players reach high levels, and
# they could not until the 2026-09-05 early-game pass. This reports how far the live population
# has actually climbed, so the balance work can be re-opened when there is real data behind it.
#
# Usage: bash tools/check_player_progress.sh
SSH_KEY="/c/Users/Dexto/Desktop/PhantomBadlandsSSH/ssh-key-2026-04-21.key"
SERVER="ubuntu@5.78.217.135"
DIR="/home/ubuntu/.local/share/godot/app_userdata/PhantomBadlands/data/characters"

ssh -i "$SSH_KEY" "$SERVER" "python3 - <<'PY'
import json, glob, collections
rows = []
for f in glob.glob('$DIR/*.json'):
    if f.endswith('.bak'):
        continue
    try:
        d = json.load(open(f))
    except Exception:
        continue
    if not d.get('class'):
        continue
    rows.append((int(d.get('level', 1)), d.get('name'), d.get('class')))
rows.sort(reverse=True)
print('live characters: %d' % len(rows))
print()
print('%-6s %-18s %s' % ('level', 'name', 'class'))
for lv, n, c in rows[:12]:
    print('%-6d %-18s %s' % (lv, n, c))
print()
band = collections.Counter()
for lv, _, _ in rows:
    if lv < 10: band['  1-9  '] += 1
    elif lv < 25: band[' 10-24 '] += 1
    elif lv < 50: band[' 25-49 '] += 1
    elif lv < 100: band[' 50-99 '] += 1
    else: band['100+   '] += 1
print('distribution:')
for k in ['  1-9  ', ' 10-24 ', ' 25-49 ', ' 50-99 ', '100+   ']:
    if band[k]:
        print('  %s %s (%d)' % (k, '#' * band[k], band[k]))
top = rows[0][0] if rows else 0
print()
print('highest level: %d' % top)
if top >= 50:
    print('>> ACTIONABLE: characters past L50 exist. The high-level balance work can now be')
    print('   validated against real data instead of the lootsim extrapolation. Re-open the')
    print('   class table and the difficulty fit at the levels people have actually reached.')
elif top >= 25:
    print('>> Characters past L25 exist - beyond the range grown characters could reach.')
    print('   Worth re-running calibrate to check make_char against them.')
else:
    print('>> Still inside the range already measured. Nothing to re-open yet.')
PY"
