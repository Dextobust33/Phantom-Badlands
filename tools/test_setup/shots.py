#!/usr/bin/env python3
"""Capture real in-game screenshots for the website, unattended.

The site needs actual game art - monster ASCII, battler sprites, companions, dungeon floors -
and those shots go stale every time the visuals change. Driving the client by hand and pressing
F12 is exactly the setup waste this harness exists to remove, so the client scripts the states
itself (see `--shots` in client.gd) and saves each frame to claude_screenshots/.

    python tools/test_setup/shots.py                      # world, companions, combat, dungeon
    python tools/test_setup/shots.py world combat

The client is launched at a large resolution: these end up on a web page, so they want to be
crisp, not 1280x720 dev windows.

Dev only - the capture mode is gated on OS.has_feature("editor") and cannot run in a build.
"""
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import scenario as scen  # noqa: E402
import run as runner     # noqa: E402

# Dungeon BEFORE combat: entering a dungeon is refused while in a fight.
DEFAULT_SCENES = ["world", "companions", "dungeon", "combat"]
SHOT_RES = "1920x1080"   # the layout is designed for 1080p; wider just spreads it thin
# The capture walks its scenes on a fixed timeline inside the client; this is that timeline
# plus headroom. Overrunning is harmless (the client is killed); cutting it short is not.
BUDGET_S = 200


def grant_admin():
    """The capture uses GM calls (spawn a monster, grant companions, enter a dungeon), which
    are gated on an account flag. Local test accounts only - never touches production."""
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
            json.dump(db, f, indent="\t")
    print("  admin ok (%d newly granted)" % n)


def main():
    scenes = sys.argv[1:] or DEFAULT_SCENES
    if runner.live_instances():
        print("REFUSING: Godot is already running. Close it first.")
        return 1

    shots_dir = os.path.join(scen.PROJECT, "claude_screenshots")
    before = set(os.listdir(shots_dir)) if os.path.isdir(shots_dir) else set()

    print("[1/4] scenario")
    sys.argv = [sys.argv[0], "healthy"]
    if scen.main() != 0:
        return 1
    print("[2/4] credentials + admin")
    runner.set_dev_passwords(1)
    grant_admin()

    print("[3/4] server")
    subprocess.Popen([scen.GODOT, "--path", scen.PROJECT, "--screen", "1", "--windowed",
                      "--resolution", "1280x720", "server/server.tscn"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    if not runner.wait_for_server():
        print("  server never started listening")
        return 1

    print("[4/4] client capturing: %s" % ", ".join(scenes))
    user, _acc, cname, _fn = scen.PLAYERS[0]
    client = subprocess.Popen([
        scen.GODOT, "--path", scen.PROJECT, "--screen", "1", "--windowed",
        "--resolution", SHOT_RES, "client/client.tscn", "--",
        "--user=%s" % user, "--pass=%s" % runner.DEV_PASSWORD, "--char=%s" % cname,
        "--server=localhost", "--shots=%s" % ",".join(scenes)],
        stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)

    for _ in range(BUDGET_S):
        time.sleep(1)
        if client.poll() is not None:
            break

    for p in (client,):
        if p.poll() is None:
            p.terminate()
    subprocess.run(["taskkill", "/F", "/IM", "godot.windows.opt.tools.64.exe"],
                   capture_output=True)

    after = set(os.listdir(shots_dir)) if os.path.isdir(shots_dir) else set()
    new = sorted(after - before)
    print("\ncaptured %d new screenshot(s):" % len(new))
    for f in new:
        print("  claude_screenshots/%s" % f)
    return 0 if new else 1


if __name__ == "__main__":
    sys.exit(main())
