#!/bin/bash
# Deploy the server with a warned countdown, and swap in the window that countdown opens.
#
# ⛑ THE WINDOW IS SMALLER THAN THE RUNBOOK READS. 2026-09-16: the countdown ran, systemd's
# `Restart=always` brought the server back on the OLD binary a few seconds later, and the swap
# landed after that - so it took a second restart and the one player online took two disconnects.
# The order below is what avoids it:
#
#   1. export and upload as `.new` BEFORE writing the sentinel, so the file is already there
#   2. write the countdown
#   3. poll for the sentinel to be CONSUMED (that is the countdown starting, not ending)
#   4. the moment the PID changes, `mv` and restart once - the process that comes up is the new one
#
# And verify by hashing `/proc/$PID/exe`, never the file on disk: a failed swap and a successful
# one look identical in `systemctl status`.
set -euo pipefail

GODOT="D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
PROJECT="C:\Users\Dexto\Documents\phantasia-revival"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
SSH_KEY="/c/Users/Dexto/Desktop/PhantomBadlandsSSH/ssh-key-2026-04-21.key"
HOST="ubuntu@5.78.217.135"
SSH="ssh -o StrictHostKeyChecking=no -i $SSH_KEY $HOST"
COUNTDOWN="${1:-60}"

echo "  exporting server binary (headless)"
"$GODOT" --headless --path "$PROJECT" --export-release "Phantom-Badlands-Server-Linux" \
	"builds/server/PhantomBadlandsServer.x86_64" >/dev/null 2>&1
LOCAL_HASH="$(sha256sum builds/server/PhantomBadlandsServer.x86_64 | cut -d' ' -f1)"

echo "  uploading as .new (staged before the countdown, on purpose)"
scp -o StrictHostKeyChecking=no -i "$SSH_KEY" builds/server/PhantomBadlandsServer.x86_64 \
	"$HOST:~/phantom-badlands/PhantomBadlandsServer.x86_64.new" >/dev/null

BEFORE="$($SSH 'systemctl show -p MainPID --value phantom-badlands')"
echo "  running pid $BEFORE; warning players ($COUNTDOWN s)"
$SSH "echo $COUNTDOWN > ~/.local/share/godot/app_userdata/PhantomBadlands/pending_shutdown.txt"

echo "  waiting for the restart"
for _ in $(seq 1 120); do
	NOW="$($SSH 'systemctl show -p MainPID --value phantom-badlands' || true)"
	if [[ -n "$NOW" && "$NOW" != "$BEFORE" ]]; then
		break
	fi
done

echo "  swapping and restarting once"
$SSH 'cd ~/phantom-badlands && mv -f PhantomBadlandsServer.x86_64.new PhantomBadlandsServer.x86_64 && chmod +x PhantomBadlandsServer.x86_64 && sudo systemctl restart phantom-badlands'

for _ in $(seq 1 60); do
	PID="$($SSH 'systemctl show -p MainPID --value phantom-badlands' || true)"
	[[ -n "$PID" && "$PID" != "0" ]] && break
done
RUNNING_HASH="$($SSH "PID=\$(systemctl show -p MainPID --value phantom-badlands); sudo sha256sum /proc/\$PID/exe | cut -d' ' -f1")"

if [[ "$RUNNING_HASH" == "$LOCAL_HASH" ]]; then
	echo "  VERIFIED: running process is this build (${LOCAL_HASH:0:16})"
else
	echo "  FAILED: running ${RUNNING_HASH:0:16}, built ${LOCAL_HASH:0:16}" >&2
	exit 1
fi
