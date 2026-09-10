#!/usr/bin/env bash
# Did GitHub actually garbage-collect the unreachable objects we asked about?
#
# The history rewrite of 2026-09-10 made the licence-restricted art unreachable from any ref, but
# GitHub keeps unreachable objects until it GCs and still serves them BY DIRECT SHA. A support
# request was submitted the same day. This re-runs the exact measurement that proved the problem,
# so "did they do it?" is answered by fetching rather than by guessing.
#
# Exit 0 = gone (GC done). Exit 1 = still served.
set -u
REPO="Dextobust33/Phantom-Badlands"
SHAS="2d0504c4217fc9a4c57b5ecf5444321061b72cda 615b40c31c688f0916b976c95256a76c14093ce4 758bde304d48c9d6fe514660bfc4f11fa70987d6"
PATHREF="client/sprites/pet-egg-pack/LICENSE.txt"
live=0
for s in $SHAS; do
    c=$(curl -sS -o /dev/null -w '%{http_code}' -L "https://raw.githubusercontent.com/$REPO/$s/$PATHREF")
    if [ "$c" = "200" ]; then printf '  STILL SERVED  %s  (HTTP %s)\n' "${s:0:12}" "$c"; live=1
    else printf '  gone          %s  (HTTP %s)\n' "${s:0:12}" "$c"; fi
done
size=$(curl -sS "https://api.github.com/repos/$REPO" | grep -o '"size": *[0-9]*' | head -1 | tr -dc 0-9)
printf '  repo size reported by GitHub: %s KB (was 120127 KB before the rewrite)\n' "${size:-?}"
if [ "$live" -ne 0 ]; then
    echo "  -> unreachable objects are still retained; the GC has not run yet."
    exit 1
fi
echo "  -> GC appears to have run. Update docs/ASSET_LICENCES.md and close the backlog item."
