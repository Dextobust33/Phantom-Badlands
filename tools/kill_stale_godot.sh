#!/usr/bin/env bash
# Reap orphaned HEADLESS Godot processes left behind by dev tooling.
#
# Why this exists (2026-09-08): a `-- polytest` sim run was found still alive after THREE DAYS,
# pinning a core the entire time. Owner: *"Headless stale process that stick around for days is
# a problem."*
#
# How they survive: the Bash tool's `timeout` kills the SHELL it started, but on Windows the
# Godot child is not in that process group and lives on. So a sim that hangs — or a wrapper that
# is interrupted — leaves a headless process with no window, no output anyone reads, and nothing
# to make it stop.
#
# The sim now self-aborts on a wall-clock budget (see `_budget_expired` in real_combat_sim.gd),
# which handles a runaway LOOP. This handles the cases that cannot check a deadline: a true hang,
# a deadlock, or a process orphaned before the budget was armed.
#
# ONLY headless processes are touched. An editor or a running game has a window and a person
# looking at it; killing those could discard work.
#
# Usage:
#   bash tools/kill_stale_godot.sh          # report only
#   bash tools/kill_stale_godot.sh --kill   # actually reap
#   bash tools/kill_stale_godot.sh --kill --older-than 30   # minutes (default 60)

set -uo pipefail

KILL=0
OLDER_MIN=60
while [ $# -gt 0 ]; do
    case "$1" in
        --kill) KILL=1 ;;
        --older-than) OLDER_MIN="${2:-60}"; shift ;;
        *) echo "unknown option: $1"; exit 2 ;;
    esac
    shift
done

# CommandLine tells us headless-vs-windowed; CreationDate gives the age.
PS_CMD=$(cat <<'PSEOF'
$cut = (Get-Date).AddMinutes(-OLDER_MIN_PLACEHOLDER)
Get-CimInstance Win32_Process -Filter "Name = 'godot.windows.opt.tools.64.exe'" |
  Where-Object { $_.CommandLine -like '*--headless*' -and $_.CreationDate -lt $cut } |
  ForEach-Object {
    $age = [int]((Get-Date) - $_.CreationDate).TotalMinutes
    "{0}`t{1}`t{2}" -f $_.ProcessId, $age, ($_.CommandLine -replace '\s+',' ')
  }
PSEOF
)
PS_CMD="${PS_CMD/OLDER_MIN_PLACEHOLDER/$OLDER_MIN}"

mapfile -t ROWS < <(powershell.exe -NoProfile -NonInteractive -Command "$PS_CMD" 2>/dev/null | tr -d '\r' | grep -v '^$')

if [ "${#ROWS[@]}" -eq 0 ]; then
    echo "No headless Godot processes older than ${OLDER_MIN} minutes."
    exit 0
fi

echo "Stale headless Godot processes (older than ${OLDER_MIN} minutes):"
for row in "${ROWS[@]}"; do
    pid=$(echo "$row" | cut -f1)
    age=$(echo "$row" | cut -f2)
    cmd=$(echo "$row" | cut -f3 | cut -c1-110)
    printf '  pid %-8s %4s min  %s\n' "$pid" "$age" "$cmd"
done

if [ "$KILL" -ne 1 ]; then
    echo
    echo "Report only. Re-run with --kill to reap them."
    exit 0
fi

echo
for row in "${ROWS[@]}"; do
    pid=$(echo "$row" | cut -f1)
    if taskkill //PID "$pid" //F >/dev/null 2>&1; then
        echo "  killed $pid"
    else
        echo "  could not kill $pid (already gone?)"
    fi
done
