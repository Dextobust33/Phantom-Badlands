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


def set_dev_passwords(_roster):
    """Point the test accounts at a known password so the clients can log themselves in.
    Mirrors persistence_manager.hash_password: sha256(salt + password), hex.

    `_roster` is a list of (user, account, char, file) tuples, or an INT meaning "the first N
    players". 2026-09-08: shots.py called this with a bare 1 and died on
    `TypeError: 'int' object is not iterable`, so the screenshot harness had been broken for as
    long as that call had been there — which is how a UI report ("combat overlaps at 1080p")
    could sit in the backlog for months with no way to check it. Accepting the int too means the
    intent that was obviously meant now works."""
    if isinstance(_roster, int):
        _roster = scen.PLAYERS[:_roster]
    with open(scen.ACCOUNTS, encoding="utf-8") as f:
        db = json.load(f)
    wanted = {u for u, _, _, _ in _roster}
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


# Mastery thresholds, mirrored from Character.MASTERY_RANK_THRESHOLDS.
_MASTERY_THRESHOLDS = [10, 35, 100, 275, 650, 1400]


def _settle_milestones(roster):
    """Spend every owed card-upgrade milestone up front, so a test session does not open with a
    queue of rank-up popups.

    2026-09-08, owner: "you need to set me up so I don't have to click through a dozen card
    upgrades". `backfill_ability_uses_if_needed` grants a fresh character 200 uses of every
    archetype ability, which crosses three thresholds each, so a brand new test character owes
    ~20 choices before it has swung once. Each is spent on "power" here, which is the neutral
    pick - it makes the cards stronger, not different, so a UI check is not confounded."""
    n = 0
    for _u, _acc, cname, fn in roster:
        path = os.path.join(scen.SAVE_DIR, fn)
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8") as f:
            c = json.load(f)
        uses = c.get("ability_uses", {}) or {}
        picks = c.get("ability_milestone_picks", {}) or {}
        for ab, u in uses.items():
            earned = sum(1 for t in _MASTERY_THRESHOLDS if int(u) >= t)
            have = len(picks.get(ab, []))
            if earned > have:
                picks[ab] = list(picks.get(ab, [])) + ["power"] * (earned - have)
                n += earned - have
        c["ability_milestone_picks"] = picks
        c["pending_rank_choices"] = []
        with open(path, "w", encoding="utf-8") as f:
            json.dump(c, f, indent="	")
    print("  settled %d owed card upgrade(s) - no rank-up popups this session" % n)


def _grant_admin():
    """GM calls (spawn a monster, enter a dungeon) are gated on an account flag. Local test
    accounts only - never touches production."""
    with open(scen.ACCOUNTS, encoding="utf-8") as f:
        db = json.load(f)
    wanted = {u for u, _, _, _ in scen.PLAYERS}
    n = 0
    for _aid, a in db.get("accounts", {}).items():
        if a.get("username") in wanted and not a.get("is_admin", False):
            a["is_admin"] = True
            n += 1
    if n:
        with open(scen.ACCOUNTS, "w", encoding="utf-8") as f:
            json.dump(db, f, indent="	")
    print("  admin ok (%d newly granted)" % n)


def main():
    # 2026-09-08 - --only=NAME launches ONE client instead of the whole roster. Added because
    # confirming a combat-UI change needs a specific CLASS (a Ranger, for its debuff cards) and
    # opening four windows to reach one of them is its own obstacle.
    only = ""
    noranks = False
    argv = []
    for a in sys.argv[1:]:
        if a.startswith("--only="):
            only = a.split("=", 1)[1]
        elif a == "--noranks":
            noranks = True
        else:
            argv.append(a)
    sys.argv = [sys.argv[0]] + argv
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

    _roster = scen.roster_for(name)
    n = len(_roster)
    print("[1/4] scenario (%d players)" % n)
    # Widen the roster if --only names a character the scenario would not have created.
    if only:
        for _i, (_u, _acc, _cn, _fn) in enumerate(scen.PLAYERS):
            if _cn == only and _i + 1 > scen.SCENARIOS[name].get("players", 2):
                scen.SCENARIOS[name]["players"] = _i + 1
        # roster_for() was already evaluated above, against the pre-widening count.
        _roster = scen.roster_for(name)
    sys.argv = [sys.argv[0], name]
    if scen.main() != 0:
        return 1
    print("[2/4] credentials")
    set_dev_passwords(scen.PLAYERS)
    _grant_admin()
    if only:
        _roster = [r for r in _roster if r[2] == only]
        if not _roster:
            print("  no such character: %s" % only)
            return 1

    # Capture stdout per process. Godot's user:// log does NOT capture print(), so a
    # diagnostic added to a client is invisible without this.
    logdir = os.path.join(PROJECT, "tools", "test_setup", "logs")
    if not os.path.isdir(logdir):
        os.makedirs(logdir)
    for old_log in os.listdir(logdir):
        if old_log.endswith(".log"):
            os.remove(os.path.join(logdir, old_log))

    # --autoact: non-leader members auto-attack so ONE person can test a party fight. Without
    # it a co-op round never resolves unless you alt-tab and act in every window, which reads
    # as "nothing happened" rather than "you are still waiting on someone".
    if noranks:
        _settle_milestones(_roster)

    print("[3/4] server (auto-party, auto-act, fight log)")
    slog = open(os.path.join(logdir, "server.log"), "w", encoding="utf-8", errors="replace")
    subprocess.Popen([GODOT, "--path", PROJECT, "--screen", "1", "--windowed",
                      "--resolution", "1280x720", "server/server.tscn", "--",
                      "--autoparty", "--autoact", "--playtest-log"],
                     stdout=slog, stderr=subprocess.STDOUT)
    if not wait_for_server():
        print("  server never started listening")
        return 1
    print("  listening on 9080")

    print("[4/4] clients")
    for i, (user, acc, cname, fn) in enumerate(_roster):
        if i:
            time.sleep(6)   # CONNECTION_RATE_LIMIT is 5s; back-to-back launches get rejected
        clog = open(os.path.join(logdir, "%s.log" % cname), "w", encoding="utf-8", errors="replace")
        subprocess.Popen([GODOT, "--path", PROJECT, "--screen", "1", "--windowed",
                          "--resolution", "1280x720", "client/client.tscn", "--",
                          "--user=%s" % user, "--pass=%s" % DEV_PASSWORD, "--char=%s" % cname,
                          # Force the LOCAL server. The client remembers the last host it used,
                          # so one manual connect to production silently sends every later test
                          # run there - where these accounts do not exist.
                          "--server=localhost"], stdout=clog, stderr=subprocess.STDOUT)
        print("  %s as %s" % (user, cname))
    print("\nready - clients auto-login, auto-select, and auto-party.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
