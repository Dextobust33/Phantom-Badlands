#!/usr/bin/env python3
"""One command to get a test situation on screen.

Applies a scenario, starts the server with the dev auto-party hook, and starts the clients
already logged in on the test characters. Removes the repeated setup tax - signing in two or
three times, partying up, walking somewhere useful - before every single test.

    python tools/test_setup/run.py party3
    python tools/test_setup/run.py --list

Dev only: the auto-login and auto-party flags are ignored in exported builds
(OS.has_feature("editor") is false there), so nothing here reaches players.
"""
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


def set_dev_passwords(n):
    """Point the test accounts at a known password so the clients can log themselves in.
    Mirrors persistence_manager.hash_password: sha256(salt + password), hex."""
    with open(scen.ACCOUNTS, encoding="utf-8") as f:
        db = json.load(f)
    wanted = {u for u, _, _, _ in scen.PLAYERS[:n]}
    changed = []
    for aid, a in db.get("accounts", {}).items():
        if a.get("username") in wanted:
            salt = a.get("password_salt", "")
            a["password_hash"] = hashlib.sha256((salt + DEV_PASSWORD).encode()).hexdigest()
            changed.append(a["username"])
    with open(scen.ACCOUNTS, "w", encoding="utf-8") as f:
        json.dump(db, f, indent="\t")
    print("  dev password set for: %s" % ", ".join(changed))


def wait_for_server(timeout=25):
    for _ in range(timeout):
        out = subprocess.run(["netstat", "-an"], capture_output=True, text=True).stdout
        if any("0.0.0.0:9080" in l and "LISTENING" in l for l in out.splitlines()):
            return True
        time.sleep(1)
    return False


def live_instances():
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq godot.windows.opt.tools.64.exe",
                          "/FO", "CSV"], capture_output=True, text=True).stdout
    return len([l for l in out.splitlines() if l.startswith('"godot')])


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("--list", "-l", "-h", "--help"):
        return scen.main()
    name = sys.argv[1]
    if name not in scen.SCENARIOS:
        print("unknown scenario %r (use --list)" % name)
        return 1
    if live_instances():
        print("REFUSING: %d Godot instance(s) already running. Close them first - a second "
              "server cannot bind 9080, and the port check then sees the OLD server and reports "
              "success while the clients attach to stale code." % live_instances())
        return 1

    n = scen.players_for(name)
    print("[1/4] scenario (%d players)" % n)
    sys.argv = [sys.argv[0], name]
    if scen.main() != 0:
        return 1
    print("[2/4] credentials")
    set_dev_passwords(n)

    print("[3/4] server (auto-party)")
    subprocess.Popen([GODOT, "--path", PROJECT, "--screen", "1", "--windowed",
                      "--resolution", "1280x720", "server/server.tscn", "--", "--autoparty"])
    if not wait_for_server():
        print("  server never started listening")
        return 1
    print("  listening on 9080")

    print("[4/4] clients")
    for i, (user, acc, cname, fn) in enumerate(scen.PLAYERS[:n]):
        if i:
            time.sleep(6)   # CONNECTION_RATE_LIMIT is 5s; back-to-back launches get rejected
        subprocess.Popen([GODOT, "--path", PROJECT, "--screen", "1", "--windowed",
                          "--resolution", "1280x720", "client/client.tscn", "--",
                          "--user=%s" % user, "--pass=%s" % DEV_PASSWORD, "--char=%s" % cname,
                          # Force the LOCAL server. The client remembers the last host it used,
                          # so one manual connect to production silently sends every later test
                          # run there - where these accounts do not exist.
                          "--server=localhost"])
        print("  %s as %s" % (user, cname))
    print("\nready - clients auto-login, auto-select, and auto-party.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
