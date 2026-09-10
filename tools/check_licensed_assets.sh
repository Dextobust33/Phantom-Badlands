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

# The OTHER half of the same rule. Present on disk, ABSENT from git -- and nothing enforced the
# second half, so one `git add -f` or a careless .gitignore edit would quietly re-publish art we
# are not licensed to redistribute, in a commit that looks like any other. The whole history had
# to be rewritten once already; this is what stops a second time.
while IFS=$'	' read -r path want why; do
    case "$path" in ''|'#'*) continue;; esac
    tracked=$(git ls-files "$path" 2>/dev/null | wc -l)
    if [ "$tracked" -gt 0 ]; then
        printf '  FAIL  %-34s %s files TRACKED IN GIT - must not be published (%s)
'             "$path" "$tracked" "$why"
        fail=1
    fi
done < "$MAN"

if [ "$fail" -ne 0 ]; then
    echo
    echo "  Licence-restricted art is missing, or is tracked in git when it must not be."
    echo "  MISSING -> restore from the private backup. TRACKED -> git rm --cached it."
    echo "  These packs are licensed to USE, not to REDISTRIBUTE. See docs/ASSET_LICENCES.md."
    exit 1
fi
printf '  ok    licensed_assets       %d restricted dirs on disk, none tracked in git
' "$total"
