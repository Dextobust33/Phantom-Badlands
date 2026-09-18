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
# THE LAUNCHER SHOWS THIS. Its "Recent Changes" panel renders the GitHub release BODY, and
# from v0.9.793 to v0.9.799 that body was the one line "See the in-game What's Changed
# screen." - introduced right here, when the release was automated into one call. Owner
# 2026-09-17: *"who made the decision to stop putting the patch update notes on the
# launcher. That's literally what that section is for, undo that."* Nobody decided; the
# automation dropped it.
#
# GENERATED, not hand-written. The notes and the in-game changelog are the same information,
# so they are authored ONCE in `display_changelog()` and extracted here - otherwise they go
# stale separately, which is how this broke. `set -e` means a version with no changelog
# entry STOPS the release rather than shipping another placeholder.
NOTES="releases/release-notes-v$VERSION.md"
# ⛑ AND A NAME, NOT JUST A NUMBER. The launcher draws a release's `name` as a gold bold
# heading, and this passed "v0.9.802" - so the heading said the version and every headline
# point sat undifferentiated in the body below it. Owner 2026-09-17: *"bring back the
# summary line/update name ... instead of just the version number and a wall of text."*
TITLE_FILE="releases/release-title-v$VERSION.txt"
python tools/make_release_notes.py "$VERSION" -o "$NOTES" --title-out "$TITLE_FILE"
RELEASE_TITLE="$(cat "$TITLE_FILE" 2>/dev/null)"
[ -n "$RELEASE_TITLE" ] || RELEASE_TITLE="v$VERSION"
echo "  title: $RELEASE_TITLE"
# ⛑ CREATE BARE, THEN ATTACH ONE AT A TIME. Attaching the assets to `gh release create`
# means ONE flaky upload destroys the whole release: `gh` deletes the release it just made,
# so the tag never appears and the build is wasted.
#
# That is not hypothetical. v0.9.802 hit **HTTP 500 "Error creating asset temp dir"** twice in
# a row, on two DIFFERENT assets - transient GitHub flakiness on large uploads, not a bad file.
# Both attempts rolled back a complete, gate-passed build.
#
# A release with no assets is something you can add to; a failed create is something you have
# to redo. Now a 500 costs one retry of one file.
# ⛑ AND A RE-RUN MUST NOT DIE ON ITS OWN TAG. 2026-09-18: a release run was interrupted after it
# had created the release; every retry then hit `HTTP 422 Release.tag_name already exists`, took
# the script's exit code to 1, and reported failure for a release that had in fact completed -
# assets attached, server deployed and hash-verified. The whole point of "create bare, then attach
# one at a time" is that a half-finished release is something you can finish; that only holds if
# finishing it is not blocked by the half that already exists.
if gh release view "v$VERSION" >/dev/null 2>&1; then
  echo "  release v$VERSION already exists - updating its notes and attaching assets"
  gh release edit "v$VERSION" --title "$RELEASE_TITLE" --notes-file "$NOTES"
else
  gh release create "v$VERSION" --title "$RELEASE_TITLE" --notes-file "$NOTES"
fi

for asset in \
	"releases/phantom-badlands-client-v$VERSION.zip" \
	"releases/phantom-badlands-launcher.zip" \
	"releases/phantom-badlands-client-linux-v$VERSION.zip" \
	"releases/phantom-badlands-launcher-linux.zip" \
	"releases/phantom-badlands-pck-v$VERSION.zip" \
	"releases/phantom-badlands-runtime-r$RUNTIME.zip" \
	"releases/client-manifest.json"
do
	uploaded=0
	for attempt in 1 2 3 4; do
		if gh release upload "v$VERSION" "$asset" --clobber >/dev/null 2>&1; then
			uploaded=1; break
		fi
		echo "  retry $attempt: $(basename "$asset")"
		sleep 5
	done
	# A HARD failure, named. A release missing its Linux launcher is worse than no release:
	# the website serves both platforms and the launcher self-updates from these URLs, so a
	# silent gap breaks new-player downloads rather than merely inconveniencing them.
	if [ "$uploaded" != "1" ]; then
		echo "FAILED to upload $asset after 4 attempts" >&2
		exit 1
	fi
	echo "  ok  $(basename "$asset")"
done

if [[ "$WITH_SERVER" == "1" ]]; then
	step "Server deploy (countdown, swap, verify)"
	bash tools/deploy_server_warned.sh
fi

step "Done - v$VERSION"
