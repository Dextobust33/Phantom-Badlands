#!/usr/bin/env python3
"""One command to get a co-op test situation on screen.

Applies a scenario, starts the server with the dev auto-party hook, and starts two clients
already logged in on the test characters. Removes the repeated setup tax — signing in twice,
partying up, walking somewhere useful — before every single test.

    python tools/test_setup/run.py near_death_one
    python tools/test_setup/run.py --list

Dev only: the auto-login and auto-party flags are ignored in exported builds
(OS.has_feature("editor") is false there), so nothing here reaches players.
"""
import hashlib, json, os, subprocess, sys, time

GODOT = r"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
PROJECT = r"C:\Users\Dexto\Documents\phantasia-revival"
DATA = os.path.expandvars(r"%APPDATA%\Godot\app_userdata\PhantomBadlands\data")
DEV_PASSWORD = "devtest"

# account username -> character to play
PLAYERS = [("Testing", "test02"), ("Testing2", "test002")]

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import scenario as scen  # noqa: E402


def set_dev_passwords():
    """Point the test accounts at a known password so the clients can log themselves in.
    Mirrors persistence_manager.hash_password: sha256(salt + password), hex."""
    path = os.path.join(DATA, "accounts.json")
    with open(path, encoding="utf-8") as f:
        db = json.load(f)
    changed = []
    for aid, a in db.get("accounts", {}).items():
        if a.get("username") in [u for u, _ in PLAYERS]:
            salt = a.get("password_salt", "")
            a["password_hash"] = hashlib.sha256((salt + DEV_PASSWORD).encode()).hexdigest()
            changed.append(a["username"])
    with open(path, "w", encoding="utf-8") as f:
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
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq godot.windows.opt.tools.64.exe", "/FO", "CSV"],
                         capture_output=True, text=True).stdout
    return max(0, len([l for l in out.splitlines() if l.startswith('"godot')]))


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("--list", "-l", "-h", "--help"):
        return scen.main()
    name = sys.argv[1]
    if name not in scen.SCENARIOS:
        print("unknown scenario %r (use --list)" % name)
        return 1
    if live_instances():
        print("REFUSING: %d Godot instance(s) already running. Close them first — a second server "
              "cannot bind 9080 and the clients would silently attach to the OLD one." % live_instances())
        return 1

    print("[1/4] scenario")
    sys.argv = [sys.argv[0], name]
    if scen.main() != 0:
        return 1
    print("[2/4] credentials")
    set_dev_passwords()

    print("[3/4] server (auto-party)")
    subprocess.Popen([GODOT, "--path", PROJECT, "--screen", "1", "--windowed",
                      "--resolution", "1280x720", "server/server.tscn", "--", "--autoparty"])
    if not wait_for_server():
        print("  server never started listening")
        return 1
    print("  listening on 9080")

    print("[4/4] clients")
    for i, (user, char) in enumerate(PLAYERS):
        if i:
            time.sleep(6)   # CONNECTION_RATE_LIMIT is 5s; back-to-back launches get rejected
        subprocess.Popen([GODOT, "--path", PROJECT, "--screen", "1", "--windowed",
                          "--resolution", "1280x720", "client/client.tscn", "--",
                          "--user=%s" % user, "--pass=%s" % DEV_PASSWORD, "--char=%s" % char])
        print("  %s as %s" % (user, char))
    print("\nready — both clients auto-login, auto-select, and auto-party.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
