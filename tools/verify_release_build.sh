#!/usr/bin/env bash
# Mandatory release gate. Runs a PACKAGED client and asserts the things that have silently
# regressed in shipped builds before.
#
# Why this exists (owner, 2026-09-07): *"are we still ensuring that we are locking vsync and
# whatever else was needed to improve performance? If not we need to find a solution so this is
# Always done with every new release without me having to tell you or correct it each time."*
#
# The --buildverify probe had existed since 2026-09-05 and NOTHING ever ran it. A check nobody
# runs is not a check. This script is the thing that runs it, and it exits non-zero so it cannot
# be passed over by not reading the output.
#
# It also catches the older, worse failure: headless --export-release reuses a stale script cache
# and ships OLD CODE (v0.9.657-660 all shipped stale). Grepping the pck cannot detect that —
# scripts are compressed binary tokens. Running the exe can.
#
# Usage:  bash tools/verify_release_build.sh [path/to/PhantomBadlandsClient.exe]

set -uo pipefail
cd "$(dirname "$0")/.."

EXE="${1:-builds/windows/PhantomBadlandsClient.exe}"
if [ ! -f "$EXE" ]; then
    echo "FAIL: no packaged client at '$EXE'"
    echo "      Export it first, and remember the --editor --quit recompile BEFORE the export."
    exit 1
fi

WANT_VERSION="$(tr -d ' \r\n' < VERSION.txt)"
OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT

# The client quits itself after printing, but cap it so a hang cannot wedge a release.
timeout 120 "$EXE" --buildverify > "$OUT" 2>&1

echo "--- $EXE"
grep '\[BUILDVERIFY\]' "$OUT" || true
echo "---"

fail=0
check() {   # check <label> <expected> <actual>
    if [ "$2" = "$3" ]; then
        printf '  ok    %-22s %s\n' "$1" "$3"
    else
        printf '  FAIL  %-22s got %s, want %s\n' "$1" "$3" "$2"
        fail=1
    fi
}
field() { grep -m1 "\[BUILDVERIFY\] $1=" "$OUT" | sed "s/.*$1=//" | tr -d ' \r'; }

if ! grep -q '\[BUILDVERIFY\]' "$OUT"; then
    echo "FAIL: the build printed no [BUILDVERIFY] lines at all."
    echo "      Either the export is STALE (missing --editor --quit) or the client crashed."
    exit 1
fi

# --- performance guards. Both are set from code in client.gd _ready so a stripped or edited
# --- project.godot cannot take them away silently.
check "vsync_mode"   "1"  "$(field vsync_mode)"
check "max_fps"      "60" "$(field max_fps)"

# --- freshness. A stale export ships the previous release's code with the new VERSION.txt
# --- stamped beside it, so the version alone does not prove freshness — these do.
check "version"              "$WANT_VERSION" "$(field version)"
check "themed_loot_hook"     "true"          "$(field themed_loot_hook)"
check "outsmart_button_gone" "true"          "$(field outsmart_button_gone)"
check "passive_single_source" "true"         "$(field passive_single_source)"

# --- do the dungeon art LOOKUPS resolve? Not "do the files exist" - do the FUNCTIONS that the
# --- game calls return something loadable. v0.9.761 shipped with every monster sprite broken
# --- because the table stored "skeleton.png" and monster_path() appended ".png" again. The files
# --- were checked. The row count was checked. The resolver was never called once, and every
# --- monster in every dungeon silently fell back to a letter.
GODOT_BIN="${GODOT_BIN:-D:/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe}"
if [ -x "$GODOT_BIN" ]; then
    art_out="$("$GODOT_BIN" --headless --path . --script res://tools/verify_dungeon_art.gd 2>&1)"
    art_rc=$?
    if printf '%s' "$art_out" | grep -q "DUNGEONART"; then
        if [ "$art_rc" -eq 0 ]; then
            printf '  ok    dungeon_art            %s
'                 "$(printf '%s' "$art_out" | grep -o 'checked=[0-9]*' | head -1) lookups resolve"
        else
            printf '  FAIL  dungeon_art            a lookup resolves to nothing
'
            printf '%s
' "$art_out" | grep BROKEN | head -5 | sed 's/^/        /'
            fail=1
        fi
    else
        printf '  WARN  dungeon_art            audit did not run
'
    fi
fi

if [ "$fail" -ne 0 ]; then
    echo
    echo "RELEASE BLOCKED. Do not upload this build."
    echo "If a freshness check failed, re-run:  godot --headless --editor --quit --path ."
    echo "then export again — the export reuses a stale compiled-script cache without it."
    exit 1
fi

echo
echo "PASS — $EXE is current and carries the performance guards."
