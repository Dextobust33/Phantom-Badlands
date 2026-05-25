#!/bin/bash
# Build the Linux client + launcher release artifacts for Phantom Badlands.
# Mirrors the Windows release flow in CLAUDE.md, for the Linux platform.
# Usage: bash build_linux_release.sh
#
# Produces (in releases/):
#   phantom-badlands-client-linux-vX.Y.Z.zip   (binary + sqlite .so + VERSION + CREDITS)
#   phantom-badlands-launcher-linux.zip         (launcher binary)
#
# NOTE: the Linux client embeds its PCK (single binary). The sqlite .so must sit
# next to the binary (same flat layout the production Linux server uses).

set -e
GODOT="D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
PROJECT="C:\Users\Dexto\Documents\phantasia-revival"
SQLITE_SO="addons/godot-sqlite/bin/libgdsqlite.linux.template_release.x86_64.so"
VERSION=$(tr -d ' \r\n' < VERSION.txt)

echo "=== Phantom Badlands Linux Release Build (v$VERSION) ==="

# Step 1: Export Linux client (single binary, PCK embedded)
echo "[1/4] Exporting Linux client..."
mkdir -p builds/linux
"$GODOT" --path "$PROJECT" --export-release "Phantom-Badlands-Linux" "builds/linux/PhantomBadlandsClient.x86_64" 2>&1 | tail -1

# Step 2: Export Linux launcher (single binary)
echo "[2/4] Exporting Linux launcher..."
"$GODOT" --path "$PROJECT/launcher" --export-release "Linux" "../builds/PhantomBadlandsLauncher.x86_64" 2>&1 | tail -1

# Step 3: Stage client payload (binary + sqlite .so + metadata)
echo "[3/4] Staging client payload..."
cp "$SQLITE_SO" builds/linux/libgdsqlite.linux.template_release.x86_64.so
cp VERSION.txt builds/linux/VERSION.txt
cp CREDITS.md  builds/linux/CREDITS.md

# Step 4: Create release ZIPs (Compress-Archive — exec bit restored by launcher chmod)
echo "[4/4] Creating release ZIPs..."
mkdir -p releases
powershell -Command "Compress-Archive -Path 'builds/linux/PhantomBadlandsClient.x86_64', 'builds/linux/libgdsqlite.linux.template_release.x86_64.so', 'builds/linux/VERSION.txt', 'builds/linux/CREDITS.md' -DestinationPath 'releases/phantom-badlands-client-linux-v$VERSION.zip' -Force"
powershell -Command "Compress-Archive -Path 'builds/PhantomBadlandsLauncher.x86_64' -DestinationPath 'releases/phantom-badlands-launcher-linux.zip' -Force"

echo ""
echo "=== Linux release build complete ==="
echo "  releases/phantom-badlands-client-linux-v$VERSION.zip"
echo "  releases/phantom-badlands-launcher-linux.zip"
