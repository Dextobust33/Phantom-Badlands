#!/usr/bin/env bash
# Is the licence-restricted art actually present?
#
# Those packs are USED under licence but may not be REDISTRIBUTED, so they are not in git (see
# docs/ASSET_LICENCES.md). A fresh clone therefore builds a game with holes in the floor and
# nothing complains -- the dungeon simply falls back to letters and blank tiles, which looks like
# a rendering bug rather than a missing checkout. This turns that into a loud failure.
#
# Wired into tools/verify_release_build.sh so a release can never ship without them.
set -u
MAN="$(dirname "$0")/licensed_assets.manifest"
fail=0; total=0

if [ "${1:-}" = "--update" ]; then
    tmp="$(mktemp)"; head -3 "$MAN" > "$tmp"; echo >> "$tmp"
    grep -v '^#' "$MAN" | grep -v '^$' | while IFS=$'\t' read -r p _ why; do
        n=$(find "$p" -name '*.png' 2>/dev/null | wc -l)
        printf '%s\t%s\t%s\n' "$p" "$n" "$why" >> "$tmp"
    done
    mv "$tmp" "$MAN"; echo "manifest counts refreshed"; exit 0
fi

while IFS=$'\t' read -r path want why; do
    case "$path" in ''|'#'*) continue;; esac
    total=$((total+1))
    got=$(find "$path" -name '*.png' 2>/dev/null | wc -l)
    if [ ! -d "$path" ]; then
        printf '  FAIL  %-34s MISSING ENTIRELY   (%s)\n' "$path" "$why"; fail=1
    elif [ "$got" -lt "$want" ]; then
        printf '  FAIL  %-34s %s/%s files        (%s)\n' "$path" "$got" "$want" "$why"; fail=1
    fi
done < "$MAN"

if [ "$fail" -ne 0 ]; then
    echo
    echo "  Licence-restricted art is missing. It is deliberately NOT in git."
    echo "  Restore it from the private backup, then re-run. See docs/ASSET_LICENCES.md."
    exit 1
fi
printf '  ok    licensed_assets       all %d restricted art directories present\n' "$total"
