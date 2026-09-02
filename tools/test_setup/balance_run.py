#!/usr/bin/env python3
"""Launch a ONE-PLAYER balance playtest at a chosen level.

    python tools/test_setup/balance_run.py 5
    python tools/test_setup/balance_run.py 100 --class Wizard

Builds test003 as the reference player the monster model is tuned against (level-appropriate
gear rolled from the real drop tables, a tier-appropriate companion at your level), starts the
server, and logs a single client in. Then fight exact-level monsters with:

    /spawnmonster Orc <level>

WHY a dedicated runner: run.py drives the party scenarios off PLAYERS[:n], whose first entry is
test02, a Wizard fixture other scenarios depend on. Rebuilding that character to test balance
would quietly break party_support and friends. This touches only test003.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import scenario as scen  # noqa: E402

GODOT = scen.GODOT
PROJECT = scen.PROJECT
DEV_PASSWORD = "devtest"
USER, ACC, CHAR = "Testing3", "acc_6", "test003"


def godot_running():
    """Count live Godot processes.

    Do NOT match tasklist's default table output against the full executable name: the
    IMAGENAME column is TRUNCATED (godot.windows.opt.tools.64.exe shows as
    "godot.windows.opt.tools.6..."), so a substring test for the full name never matches and
    the guard silently passes. That is how a second server got started on top of a running one
    during a playtest - the stale server still held the old character in memory and wrote it
    back over the rebuilt fixture. CSV output is untruncated.
    """
    out = subprocess.run(["tasklist", "/FO", "CSV", "/NH",
                          "/FI", "IMAGENAME eq godot.windows.opt.tools.64.exe"],
                         capture_output=True, text=True).stdout
    return sum(1 for line in out.splitlines() if line.lower().startswith('"godot'))


def set_dev_password():
    with open(scen.ACCOUNTS, encoding="utf-8") as f:
        db = json.load(f)
    for a in db.get("accounts", {}).values():
        if a.get("username") == USER:
            salt = a.get("password_salt", "")
            a["password_hash"] = hashlib.sha256((salt + DEV_PASSWORD).encode()).hexdigest()
            with open(scen.ACCOUNTS, "w", encoding="utf-8") as f2:
                json.dump(db, f2, indent="\t")
            return True
    return False


def wait_for_server(timeout=25):
    for _ in range(timeout):
        out = subprocess.run(["netstat", "-an"], capture_output=True, text=True).stdout
        if any("0.0.0.0:9080" in l and "LISTENING" in l for l in out.splitlines()):
            return True
        time.sleep(1)
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("level", type=int)
    ap.add_argument("--class", dest="klass", default="Fighter")
    ap.add_argument("--race", default="Human")
    args = ap.parse_args()

    if godot_running():
        print("REFUSING: Godot already running. Close it - a second server cannot bind 9080, "
              "and the port check would then see the OLD server while the client attaches to "
              "stale code.")
        return 1

    print("[1/4] building the reference player at L%d (%s %s)" % (args.level, args.race, args.klass))
    r = subprocess.run([GODOT, "--headless", "--path", PROJECT, "--script",
                        "res://tools/test_setup/balance_char.gd", "--",
                        "--acc=%s" % ACC, "--name=%s" % CHAR,
                        "--class=%s" % args.klass, "--race=%s" % args.race,
                        "--level=%d" % args.level], capture_output=True, text=True)
    for line in r.stdout.splitlines():
        if line.startswith("built"):
            print("  " + line)

    print("[2/4] credentials")
    print("  ok" if set_dev_password() else "  WARNING: account %s not found" % USER)

    logdir = os.path.join(PROJECT, "tools", "test_setup", "logs")
    os.makedirs(logdir, exist_ok=True)

    print("[3/4] server")
    slog = open(os.path.join(logdir, "server.log"), "w", encoding="utf-8", errors="replace")
    subprocess.Popen([GODOT, "--path", PROJECT, "--screen", "1", "--windowed",
                      "--resolution", "1280x720", "server/server.tscn"],
                     stdout=slog, stderr=subprocess.STDOUT)
    if not wait_for_server():
        print("  server never started listening")
        return 1
    print("  listening on 9080")

    print("[4/4] client")
    clog = open(os.path.join(logdir, "%s.log" % CHAR), "w", encoding="utf-8", errors="replace")
    subprocess.Popen([GODOT, "--path", PROJECT, "--screen", "1", "--windowed",
                      "client/client.tscn", "--",
                      "--user=%s" % USER, "--pass=%s" % DEV_PASSWORD, "--char=%s" % CHAR,
                      "--server=localhost"], stdout=clog, stderr=subprocess.STDOUT)
    print("  %s as %s (L%d)" % (USER, CHAR, args.level))
    print("\nready. In game, start an exact-level fight with:")
    print("    /spawnmonster Orc %d" % args.level)
    return 0


if __name__ == "__main__":
    sys.exit(main())
