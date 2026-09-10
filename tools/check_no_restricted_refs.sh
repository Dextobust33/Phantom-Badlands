#!/usr/bin/env bash
# Is licence-restricted art reachable from ANY ref on the REMOTE?
#
# This exists because the first verification of the 2026-09-10 history rewrite asked the wrong
# repository. It confirmed "0 restricted blobs reachable" in the LOCAL clone and called the job
# done -- but three release tags (v0.9.764/765/766) and a release branch existed only on the
# remote, having been created server-side by `gh release create`. `git push --force --tags` pushes
# LOCAL tags, so those four refs were never rewritten, still pointed into the old history, and
# still served every restricted file with HTTP 200. That is not "cached unreachable objects" that
# a GC would clear -- it is live, referenced, browsable content.
#
# So the instrument is the REMOTE ref list, never the local one.
set -u
REPO_URL="${1:-origin}"
RESTRICTED='sprites/(darkcave|darkcave_tiles|tilemap_pack|pet-egg-pack|prop_floor32|free_floor32|tile_floor32|egg_floor32|raven)/'
fail=0

tmp="$(mktemp)"; git ls-remote "$REPO_URL" > "$tmp" 2>/dev/null
total=$(grep -c . "$tmp")
echo "  remote advertises $total refs"

missing=0
while read -r sha ref; do
    case "$ref" in *'^{}') continue;; esac
    if ! git cat-file -e "$sha" 2>/dev/null; then
        printf '  FAIL  %-46s points at a commit absent locally - cannot audit it\n' "$ref"
        missing=$((missing+1)); fail=1
        continue
    fi
    n=$(git ls-tree -r "$sha" --name-only 2>/dev/null | grep -cE "$RESTRICTED")
    if [ "$n" -gt 0 ]; then
        printf '  FAIL  %-46s %s restricted files reachable\n' "$ref" "$n"; fail=1
    fi
done < "$tmp"
rm -f "$tmp"

if [ "$fail" -eq 0 ]; then
    echo "  ok    no restricted art is reachable from any remote ref"
else
    [ "$missing" -gt 0 ] && echo "  (fetch those refs before trusting this result: git fetch origin '+refs/*:refs/remotes/audit/*')"
fi
exit $fail
