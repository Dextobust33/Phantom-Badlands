#!/bin/bash
# ⚑ ONE CALL SHIPS A RELEASE, AND NOTHING OPENS A WINDOW.
#
# Owner 2026-09-16: *"Is there any way to make these releases less annoying for me? They do take a
# while and randomly pop up godot multiple times on my screen taking over whatever I'm doing on my
# primary monitor."*
#
# Two separate annoyances, both fixed here:
#
#   1. THE WINDOWS. `build_linux_release.sh` ran two `--export-release` calls without `--headless`,
#      which is a full Godot editor window on the primary monitor each time. Every Godot call in
#      this script and in the ones it calls is headless now. If you ever add one, add `--headless`
#      with it - an export does not need a window and will happily steal focus mid-sentence.
#
#   2. THE BABYSITTING. The release was a dozen hand-run steps in CLAUDE.md, each waiting on the
#      last. This runs them in order, stops at the first failure, and prints one line per step so
#      an unattended run can be read afterwards rather than watched.
#
# Usage:
#   bash tools/release.sh 0.9.794                # client only (no server deploy)
#   bash tools/release.sh 0.9.794 --with-server  # ...and deploy the server with a countdown
#   bash tools/release.sh 0.9.794 --dry-run      # build and gate, publish nothing
#
# The gate is not optional: if `verify_release_build.sh` fails, nothing is uploaded. That script
# exists because a stale script cache ships OLD code with the NEW version stamped beside it, and
# the version alone proves nothing.
set -euo pipefail

GODOT="D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
PROJECT="C:\Users\Dexto\Documents\phantasia-revival"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
	echo "usage: bash tools/release.sh <version> [--with-server] [--dry-run]" >&2
	exit 2
fi
shift
WITH_SERVER=0
DRY_RUN=0
for arg in "$@"; do
	case "$arg" in
		--with-server) WITH_SERVER=1 ;;
		--dry-run) DRY_RUN=1 ;;
		*) echo "unknown flag: $arg" >&2; exit 2 ;;
	esac
done

STEP=0
step() { STEP=$((STEP+1)); echo ""; echo "=== [$STEP] $* ==="; }

step "Version $VERSION"
echo "$VERSION" > VERSION.txt
RUNTIME="$(tr -d ' \r\n' < RUNTIME_VERSION.txt)"
echo "  content v$VERSION, runtime r$RUNTIME"

step "Recompiling scripts (client + launcher projects)"
# MANDATORY. Without it `--export-release` reuses a stale compiled-script cache and ships old code;
# v0.9.657-660 all shipped stale exactly this way. `rm -rf .godot` does NOT fix it.
"$GODOT" --headless --editor --quit --path "$PROJECT" 2>&1 | grep -i "SCRIPT ERROR" && exit 1 || true
"$GODOT" --headless --editor --quit --path "$PROJECT/launcher" 2>&1 | grep -i "SCRIPT ERROR" && exit 1 || true
echo "  ok"

step "Exporting Windows client + launcher"
"$GODOT" --headless --path "$PROJECT" --export-release "Phantom-Badlands" "builds/windows/PhantomBadlandsClient.exe" >/dev/null 2>&1
"$GODOT" --headless --path "$PROJECT/launcher" --export-release "Windows Desktop" "../builds/windows/PhantomBadlandsLauncher.exe" >/dev/null 2>&1
# VERSION.txt is a SIDECAR, not packed content - the client reads the copy beside the exe, so
# bumping the repo root alone leaves the build reporting the PREVIOUS version.
cp VERSION.txt builds/windows/VERSION.txt
echo "  ok"

step "Release gate"
bash tools/verify_release_build.sh builds/windows/PhantomBadlandsClient.exe

step "Exporting Linux client + launcher"
bash build_linux_release.sh >/dev/null
echo "  ok"

step "Zipping Windows assets"
powershell -NoProfile -ExecutionPolicy Bypass -File tools/stage_windows_zips.ps1 -Version "$VERSION" -Runtime "$RUNTIME"

step "Manifest"
python tools/make_client_manifest.py

if [[ "$DRY_RUN" == "1" ]]; then
	step "Dry run - built and gated, publishing nothing"
	ls -1 releases/*.zip releases/client-manifest.json
	exit 0
fi

step "Committing and pushing the version bump"
git add -A VERSION.txt
git diff --cached --quiet || git commit -q -m "v$VERSION"
git push -q origin master
echo "  ok"

step "GitHub release v$VERSION"
gh release create "v$VERSION" --title "v$VERSION" --notes "See the in-game What's Changed screen." \
	"releases/phantom-badlands-client-v$VERSION.zip" \
	"releases/phantom-badlands-launcher.zip" \
	"releases/phantom-badlands-client-linux-v$VERSION.zip" \
	"releases/phantom-badlands-launcher-linux.zip" \
	"releases/phantom-badlands-pck-v$VERSION.zip" \
	"releases/phantom-badlands-runtime-r$RUNTIME.zip" \
	"releases/client-manifest.json"

if [[ "$WITH_SERVER" == "1" ]]; then
	step "Server deploy (countdown, swap, verify)"
	bash tools/deploy_server_warned.sh
fi

step "Done - v$VERSION"
