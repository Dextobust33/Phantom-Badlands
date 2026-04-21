#!/bin/bash
# Deploy Phantom Badlands server to Oracle Cloud
# Usage: bash deploy_server.sh

SSH_KEY="/c/Users/Dexto/Desktop/PhantomBadlandsSSH/ssh-key-2026-04-21.key"
SERVER_IP="129.213.166.185"
SERVER_USER="ubuntu"
GODOT="D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
PROJECT="C:\Users\Dexto\Documents\phantasia-revival"

echo "=== Phantom Badlands Server Deploy ==="

# Step 1: Export Linux server binary
echo "[1/4] Exporting Linux server binary..."
"$GODOT" --path "$PROJECT" --export-release "Phantom-Badlands-Server-Linux" "builds/server/PhantomBadlandsServer.x86_64" 2>&1 | tail -1

# Step 2: Stop service, upload, start service (the running binary holds a file lock)
echo "[2/4] Stopping service and uploading..."
ssh -i "$SSH_KEY" ${SERVER_USER}@${SERVER_IP} "sudo systemctl stop phantom-badlands"
scp -i "$SSH_KEY" "$PROJECT/builds/server/PhantomBadlandsServer.x86_64" ${SERVER_USER}@${SERVER_IP}:~/phantom-badlands/
scp -i "$SSH_KEY" "$PROJECT/server_override.cfg" ${SERVER_USER}@${SERVER_IP}:~/phantom-badlands/override.cfg

# Step 3: Start service
echo "[3/4] Starting server..."
ssh -i "$SSH_KEY" ${SERVER_USER}@${SERVER_IP} "chmod +x ~/phantom-badlands/PhantomBadlandsServer.x86_64 && sudo systemctl start phantom-badlands"

# Step 4: Verify
echo "[4/4] Verifying..."
sleep 5
ssh -i "$SSH_KEY" ${SERVER_USER}@${SERVER_IP} "sudo systemctl status phantom-badlands --no-pager | head -5"

echo ""
echo "=== Deploy complete ==="
