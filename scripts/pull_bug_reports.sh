#!/bin/bash
# Pull bug reports from the Hetzner production server to a local folder.
# v0.9.571 — designed for token-efficient Claude review: one JSON file per
# report (~2 KB each), structured for direct paste into the assistant.
#
# Usage:
#   bash scripts/pull_bug_reports.sh
#
# Output:
#   ./bug_reports/<ts>_<player>.json — one file per submitted report
#   ./bug_reports/_index.txt          — one-line summary per report (ts | player | desc[:60])
#
# Tips for handing reports to Claude:
#   1. Run this script.
#   2. `cat bug_reports/_index.txt` to pick which one(s) to investigate.
#   3. `cat bug_reports/<chosen>.json` and paste into Claude with
#      "Please investigate this bug:" — one tool turn, full context.

SSH_KEY="/c/Users/Dexto/Desktop/PhantomBadlandsSSH/ssh-key-2026-04-21.key"
SERVER_IP="5.78.217.135"
SERVER_USER="ubuntu"
# user:// on Linux resolves to ~/.local/share/godot/app_userdata/PhantomBadlands/
REMOTE_DIR="/home/${SERVER_USER}/.local/share/godot/app_userdata/PhantomBadlands/bug_reports"
LOCAL_DIR="$(dirname "$0")/../bug_reports"

mkdir -p "$LOCAL_DIR"

echo "=== Pulling bug reports from Hetzner ==="
echo "From: ${SERVER_USER}@${SERVER_IP}:${REMOTE_DIR}/"
echo "To:   ${LOCAL_DIR}/"
echo ""

# Use rsync over SSH. The trailing slash on REMOTE_DIR pulls contents
# (not the directory itself).
rsync -avz \
    -e "ssh -i \"$SSH_KEY\" -o StrictHostKeyChecking=accept-new" \
    "${SERVER_USER}@${SERVER_IP}:${REMOTE_DIR}/" \
    "${LOCAL_DIR}/" \
    2>&1 | tail -20

echo ""
echo "=== Rebuilding _index.txt ==="
# Build a one-line summary per JSON file so the user can scan and pick.
# Format: <ts> | <player> | <desc truncated to 60 chars>
INDEX="${LOCAL_DIR}/_index.txt"
: > "$INDEX"
shopt -s nullglob
for f in "${LOCAL_DIR}"/*.json; do
    # Parse minimally with jq if available; fallback to grep.
    if command -v jq >/dev/null 2>&1; then
        ts=$(jq -r '.ts // .server_ts // "?"' "$f" 2>/dev/null | head -c 25)
        player=$(jq -r '.player // "?"' "$f" 2>/dev/null | head -c 20)
        desc=$(jq -r '.desc // "(no description)"' "$f" 2>/dev/null | head -c 60)
    else
        ts=$(grep -oE '"ts"[^,]*' "$f" 2>/dev/null | head -1 | cut -c 7- | tr -d '"' | head -c 25)
        player=$(grep -oE '"player":"[^"]*"' "$f" 2>/dev/null | head -1 | cut -d'"' -f4 | head -c 20)
        desc=$(grep -oE '"desc":"[^"]*"' "$f" 2>/dev/null | head -1 | cut -d'"' -f4 | head -c 60)
    fi
    printf "%s | %-20s | %s | %s\n" "$ts" "$player" "$(basename "$f")" "$desc" >> "$INDEX"
done

echo "$(wc -l < "$INDEX") reports indexed."
echo ""
echo "=== Summary ==="
ls -la "$LOCAL_DIR"/*.json 2>/dev/null | tail -10
echo ""
echo "Next: cat ${LOCAL_DIR}/_index.txt"
