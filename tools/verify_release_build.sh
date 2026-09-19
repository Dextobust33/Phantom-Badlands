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
#
# --headless, because this is the LAST thing in the release chain that opened a window.
# Owner 2026-09-16: *"I still have phantom badlands windows opening very briefly whenever
# you're doing whatever you're doing."* Verified the probe reports the same values either
# way - vsync_mode=1 and max_fps=60 are set from code in _ready, not from the window - so
# nothing the gate asserts is lost by not drawing anything.
# 180s, not 120: the art-freshness check reads every pixel of 113 packed textures.
timeout 180 "$EXE" --headless --buildverify > "$OUT" 2>&1

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
# ⛑ THE PAD BINDINGS, and they sit beside vsync/max_fps because they share the cause: all three
# are set from CODE precisely because the editor strips project.godot settings it considers
# default on every --editor --quit, which silently deleted the vsync guard from four consecutive
# release builds. Measured: the engine ships 91 default actions and only six carry ANY joypad
# binding - ui_accept and ui_cancel carry none - so without these a controller can move the
# highlight over every screen in the game and never press anything.
check "pad_bindings" "ui_accept=1,ui_cancel=1" "$(field pad_bindings)"

# --- freshness. A stale export ships the previous release's code with the new VERSION.txt
# --- stamped beside it, so the version alone does not prove freshness — these do.
check "version"              "$WANT_VERSION" "$(field version)"
check "themed_loot_hook"     "true"          "$(field themed_loot_hook)"
check "outsmart_button_gone" "true"          "$(field outsmart_button_gone)"
check "passive_single_source" "true"         "$(field passive_single_source)"
# The sprite Sanctuary's art is loaded by path and untracked; prove the packaged build has it.
check "sanctuary_sprites"    "true"          "$(field sanctuary_sprites)"
# THE OVERWORLD SPRITE PACK. Since 2026-09-17 the text map is no longer a supported MODE (owner:
# "Retire the text map"), so a build without this art is not a degraded build, it is a broken one -
# it would boot, draw the letter map, and say so where the map should be. This is the line that
# makes that fatal here rather than something a player finds.
check "overworld_art"        "true"          "$(field overworld_art)"
# v0.9.790: the off-map guide arrow (OverworldRoom.build's 7th argument).
check "mark_arrow"           "true"          "$(field mark_arrow)"
# v0.9.791: the dungeon Warden figure (client._dungeon_warden_img).
check "dungeon_warden"       "true"          "$(field dungeon_warden)"
# The state-icon sheet, loaded BY PATH. Its first home was a directory carrying a .gdignore, so
# nothing under it was imported or packed - and `ResourceLoader.exists()` still said true, while
# an [img] tag whose texture will not load draws nothing at all. A silent, invisible failure.
check "state_icons"          "true"          "$(field state_icons)"
# Every buff icon loads. A boolean, not a count: asserting "16/16" here would be a second
# copy of the table size that fails the day somebody adds a seventeenth icon.
check "buff_icons"           "true"          "$(field buff_icons)"
# The multi-cell tile manifest is a raw .json, not an imported resource - if it misses the .pck
# the map silently falls back to the shrunken 32px tiles and nothing else looks wrong.
BIG_TILES="$(field big_tiles)"
if [ "${BIG_TILES:-0}" -ge 10 ] 2>/dev/null; then
  printf '  ok    %-22s %s multi-cell tiles
' "big_tiles" "$BIG_TILES"
else
  printf '  FAIL  %-22s got "%s", want 10 or more
' "big_tiles" "$BIG_TILES"
  fail=1
fi
# â AND THE ART IN THE BUILD IS THE ART WE BAKED.
#
# Owner 2026-09-18, live, about the tile at the centre of every post: *"it was still going back to
# the sword sprite when I stepped away from it"* - a sprite replaced in a commit that is an
# ancestor of the released tag. The PNG was right on disk and right in git; the build drew the old
# picture, because Godot only re-imports on an editor pass and nothing here ever looked at a pixel.
#
# â `overworld_art` and `big_tiles` above are the INGREDIENTS - a file exists, a manifest has
# rows - and both are true of a build carrying every tile from a month ago. `--buildverify` now
# loads each packed texture and compares it against the fingerprint the baker wrote from the
# source. Any count below the full set means images are missing from the .pck; any stale one means
# the export ran on an un-imported bake.
ART_N="$(field overworld_art_checked)"
ART_STALE="$(field overworld_art_stale)"
if [ "${ART_N:-0}" -ge 100 ] 2>/dev/null && [ "${ART_STALE:-1}" = "0" ]; then
  printf '  ok    %-22s %s images, none stale
' "overworld_art_fresh" "$ART_N"
else
  printf '  FAIL  %-22s %s images checked, %s STALE (want 100+ and 0)
'     "overworld_art_fresh" "${ART_N:-0}" "${ART_STALE:-?}"
  grep "stale_art:" "$OUT" | head -12
  fail=1
fi

# The calibrated monster curve is DATA, not code, so none of the freshness probes above would
# notice it missing from an export - and without it every monster silently reverts to legacy
# base_level scaling. Added with v0.9.777, which shipped a re-calibration of the role layer.
check "curve_calibrated"     "true"          "$(field curve_calibrated)"
check "curve_roles"          "true"          "$(field curve_roles)"

# --- does the whole ASCII map fit the box it gets?
#
# Owner 2026-09-15: *"1080p players ASCII map has to be scrolled to even see the middle of their
# map."* The map font was capped to fit ACROSS (since v0.9.391) and never DOWN, so in the live
# layout - where the Travel row, the Tools overlay and the minimap share the column - a 506px map
# was drawn into a ~400px box and RichTextLabel simply scrolled. Measured, not modelled: the
# --uimeasure probe re-fits the map at the box heights a real session gives it and says whether it
# fits. Cannot be checked headlessly; a first attempt laid the scene out at 1920x1280 and reported
# that everything was fine.
UIOUT="$(mktemp)"
timeout 120 "$EXE" --uimeasure --resolution 1920x1080 > "$UIOUT" 2>&1
if grep -q '\[UIMEASURE\]' "$UIOUT"; then
    check "map_fits_its_column" "true" "$(grep -m1 'fits_reserved=' "$UIOUT" | sed 's/.*fits_reserved=//' | tr -d ' ')"
    check "map_fits_across"     "true" "$(grep -m1 'fits_across=' "$UIOUT" | sed 's/.*fits_across=//' | tr -d ' ')"
    # ...and the SAME LABEL in its other job. The live report that produced the map fix had a
    # second half - *"their area on the right for where the dungeon text goes is pretty cramped
    # as well, just like their map was"* - which sat unmeasured because an empty client hands
    # this panel the whole column. The probe now builds the real panel with a full log of
    # realistic (wrapping) entries and reports whether it fits the 610px a 1080p dungeon session
    # gives it. Underground the label holds no map grid at all, yet its font is still sized so a
    # 21-row grid would fit - so the header and the log are only just compatible with it, and
    # this is what notices when they stop being.
    check "dungeon_panel_fits"  "true" "$(grep -m1 'live_fit=' "$UIOUT" | sed 's/.*live_fit=//' | tr -d ' ')"
    # The Tools block gained a spare count ("Pickaxe T2 14/20 (2 spares)") in a 240px box, which
    # is about thirty characters - genuinely close. A wrapped tool line makes that block taller
    # and every row it gains comes out of the MAP, which is the complaint this whole section
    # exists for. Compared against the same panel with the suffix suppressed, so the control
    # differs in exactly one thing; proven to fire by lengthening the suffix.
    check "tools_panel_no_wrap"  "false" "$(grep -m1 'tools_panel with_spares=' "$UIOUT" | sed 's/.*wrapped=//' | tr -d ' ')"
else
    printf '  FAIL  %-22s %s
' "map fit" "the build printed no [UIMEASURE] lines"
    fail=1
fi
rm -f "$UIOUT"

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
