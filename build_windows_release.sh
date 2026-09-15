#!/bin/bash
# Build the Windows client + launcher release artifacts for Phantom Badlands.
# Usage: bash build_windows_release.sh
#
# Produces (in releases/):
#   phantom-badlands-client-vX.Y.Z.zip     full client (exe + pck + sqlite dll + VERSION + CREDITS)
#   phantom-badlands-launcher.zip          the launcher
#   phantom-badlands-pck-vX.Y.Z.zip        content-only delta (pck + VERSION + CREDITS)
#   phantom-badlands-runtime-rN.zip        runtime-only (exe + sqlite dll), N from RUNTIME_VERSION.txt
#   client-manifest.json                   generated, never hand-written
#
# The mirror of build_linux_release.sh. It existed only as a list of commands in CLAUDE.md, which
# is how the VERSION.txt sidecar got forgotten on v0.9.760 and the release gate had to catch it.
# Everything the gate asserts is done here, in order, so the gate confirms rather than discovers.

set -e
GODOT="D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
PROJECT="C:\Users\Dexto\Documents\phantasia-revival"
SQLITE_DLL="addons/godot-sqlite/bin/libgdsqlite.windows.template_release.x86_64.dll"
VERSION=$(tr -d ' \r\n' < VERSION.txt)
RUNTIME=$(tr -d ' \r\n' < RUNTIME_VERSION.txt)

echo "=== Phantom Badlands Windows Release Build (v$VERSION, runtime r$RUNTIME) ==="

# Step 0: force a script recompile in BOTH projects. --export-release reuses a STALE compiled
# script cache and will ship old code with the new version stamped beside it (v0.9.657-660 all
# shipped that way). Separate caches, so both projects need it.
echo "[0/5] Recompiling scripts (client + launcher projects)..."
"$GODOT" --headless --editor --quit --path "$PROJECT" 2>&1 | grep -i "SCRIPT ERROR" || true
"$GODOT" --headless --editor --quit --path "$PROJECT/launcher" 2>&1 | grep -i "SCRIPT ERROR" || true

echo "[1/5] Exporting Windows client..."
mkdir -p builds/windows
"$GODOT" --path "$PROJECT" --export-release "Phantom-Badlands" "builds/windows/PhantomBadlandsClient.exe" 2>&1 | tail -1

echo "[2/5] Exporting Windows launcher..."
"$GODOT" --path "$PROJECT/launcher" --export-release "Windows Desktop" "../builds/PhantomBadlandsLauncher.exe" 2>&1 | tail -1

# Step 3: stage the payload. VERSION.txt is a SIDECAR - it is in no preset's include_filter, so
# the client reads the copy next to the exe. Bumping it at the repo root is NOT enough; this copy
# is the one the build reports, and forgetting it is what failed the gate on v0.9.760.
echo "[3/5] Staging client payload..."
cp "$SQLITE_DLL" builds/windows/libgdsqlite.windows.template_release.x86_64.dll
cp VERSION.txt builds/windows/VERSION.txt
cp CREDITS.md  builds/windows/CREDITS.md

echo "[4/5] Creating release ZIPs..."
mkdir -p releases
powershell -Command "Compress-Archive -Path 'builds/windows/PhantomBadlandsClient.exe', 'builds/windows/PhantomBadlandsClient.pck', 'builds/windows/libgdsqlite.windows.template_release.x86_64.dll', 'builds/windows/VERSION.txt', 'builds/windows/CREDITS.md' -DestinationPath 'releases/phantom-badlands-client-v$VERSION.zip' -Force"
powershell -Command "Compress-Archive -Path 'builds/PhantomBadlandsLauncher.exe' -DestinationPath 'releases/phantom-badlands-launcher.zip' -Force"
# Split update: content and runtime travel separately so a content-only release is ~12MB, not ~100MB.
powershell -Command "Compress-Archive -Path 'builds/windows/PhantomBadlandsClient.pck', 'builds/windows/VERSION.txt', 'builds/windows/CREDITS.md' -DestinationPath 'releases/phantom-badlands-pck-v$VERSION.zip' -Force"
powershell -Command "Compress-Archive -Path 'builds/windows/PhantomBadlandsClient.exe', 'builds/windows/libgdsqlite.windows.template_release.x86_64.dll' -DestinationPath 'releases/phantom-badlands-runtime-r$RUNTIME.zip' -Force"

echo "[5/5] Generating client-manifest.json..."
python tools/make_client_manifest.py

echo ""
echo "=== Windows release build complete ==="
ls -1 releases/ | sed 's/^/  /'
echo ""
echo "NEXT: bash tools/verify_release_build.sh builds/windows/PhantomBadlandsClient.exe"
