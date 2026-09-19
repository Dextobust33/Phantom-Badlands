#!/bin/bash
# ⚑ DOES THIS SCRIPT PARSE? A yes/no you cannot accidentally throw away.
#
# 2026-09-19: a changelog edit put a bare `"` inside a GDScript string, and the broken file was
# COMMITTED, because the command was:
#
#     godot --headless --check-only --script ... 2>&1 | tail -3 && git commit ...
#
# `--check-only` prints `SCRIPT ERROR: Parse Error` and then **exits 0**, and even if it did not,
# piping it into `tail` replaces its status with tail's. So `&&` saw success and committed a file
# that would not load. CLAUDE.md already carries the general rule - *"Exit code 0 is not a pass:
# look for the probe's own PASS line"* - and this is that rule applied to the parser.
#
# So the verdict is computed from the OUTPUT, and this script's own exit status is the answer.
# Use it instead of calling --check-only by hand:
#
#     bash tools/gdcheck.sh client/client.gd shared/character.gd && git commit ...
#
# ⛑ A script that fails to PARSE also never exits when run as a --script SceneTree probe (the
# thing that would have called quit() never loaded), which is how this repo collected two
# CPU-eating zombie Godots in one session. Checking first is cheaper than finding them later.
set -uo pipefail
GODOT="${GODOT_BIN:-D:/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "$#" -eq 0 ]; then
	echo "usage: bash tools/gdcheck.sh <script.gd> [more.gd ...]" >&2
	exit 2
fi

fail=0
for f in "$@"; do
	# Accept either a repo path or a res:// path, so this is usable from anywhere.
	res="$f"
	case "$res" in
		res://*) ;;
		*) res="res://${f#./}" ;;
	esac
	out="$("$GODOT" --headless --path "$ROOT" --check-only --script "$res" 2>&1)"
	# The PARSER's own words, not the exit code. "Parse Error" covers syntax; "Failed to load
	# script" covers a file that is not there at all, which is just as much a no.
	if printf '%s' "$out" | grep -qE "Parse Error|Failed to load script|SCRIPT ERROR"; then
		printf '  FAIL  %s\n' "$f"
		printf '%s\n' "$out" | grep -E "Parse Error|SCRIPT ERROR|at: " | head -4 | sed 's/^/        /'
		fail=1
	else
		printf '  ok    %s\n' "$f"
	fi
done

if [ "$fail" -ne 0 ]; then
	echo "PARSE FAILED - do not commit"
	exit 1
fi
echo "PARSE OK"
