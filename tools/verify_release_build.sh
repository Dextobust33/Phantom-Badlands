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

# CAN THIS MACHINE EVEN RUN IT?
#
# 2026-09-09. CLAUDE.md says to gate BOTH platform builds, and on a Windows dev box that is
# impossible for the Linux one: an ELF does not execute, so the probe printed nothing and the
# script reported "the build printed no [BUILDVERIFY] lines - either the export is STALE or the
# client crashed". Both halves of that are FALSE for a cross-platform binary, and a gate that
# gives a confidently wrong diagnosis is worse than no gate: it teaches whoever reads it that a
# red result is something you wave through, which is precisely how the perf guards were lost.
#
# So say the true thing instead, and exit 0 - a SKIP is not a pass and is not a failure.
HOST="$(uname -s 2>/dev/null || echo unknown)"
IS_ELF=0
if head -c 4 "$EXE" 2>/dev/null | grep -q 'ELF'; then IS_ELF=1; fi
case "$HOST" in
    Linux*) HOST_IS_LINUX=1 ;;
    *)      HOST_IS_LINUX=0 ;;
esac
if [ "$IS_ELF" = "1" ] && [ "$HOST_IS_LINUX" = "0" ]; then
    echo "--- $EXE"
    echo "SKIPPED — this is a Linux binary and the host is $HOST, so it cannot be executed here."
    echo
    echo "  What that does and does NOT tell you:"
    echo "  - The Linux export was produced from the SAME recompiled script cache as the Windows"
    echo "    build in the same session, so if the Windows gate PASSED, the stale-cache failure"
    echo "    (the one this gate exists for) is ruled out for both."
    echo "  - vsync_mode / max_fps are set from client.gd, not project.godot, so they are shared"
    echo "    source and cannot differ between the two exports."
    echo "  - NOT verified: that this binary actually boots on Linux. Nothing on this host can"
    echo "    establish that. Run this same script on a Linux box, or in CI, to close it."
    echo
    SIDE_VER="$(tr -d ' \r\n' < "$(dirname "$EXE")/VERSION.txt" 2>/dev/null || echo '<none>')"
    if [ "$SIDE_VER" = "$WANT_VERSION" ]; then
        printf '  ok    %-22s %s\n' "sidecar version" "$SIDE_VER"
    else
        printf '  FAIL  %-22s got %s, want %s\n' "sidecar version" "$SIDE_VER" "$WANT_VERSION"
        echo
        echo "FAIL — the Linux build dir carries the wrong VERSION.txt."
        exit 1
    fi
    echo
    echo "SKIP — $EXE not executable on this host; sidecar version checked only."
    exit 0
fi

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
# The sprite Sanctuary's art is loaded by path and untracked; prove the packaged build has it.
check "sanctuary_sprites"    "true"          "$(field sanctuary_sprites)"

# --- is the licence-restricted art even PRESENT? It is not in git (docs/ASSET_LICENCES.md),
# --- so a fresh clone builds a dungeon with letters where the tiles should be and nothing says
# --- so. Cheapest possible check, and it has to run BEFORE the art lookups below, which would
# --- otherwise fail confusingly for a reason that is not their own.
if [ -f tools/check_licensed_assets.sh ]; then
    if ! bash tools/check_licensed_assets.sh; then
        fail=1
    fi
fi

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
