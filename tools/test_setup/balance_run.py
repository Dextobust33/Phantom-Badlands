#!/usr/bin/env python3
"""Launch a ONE-PLAYER balance playtest at a chosen level.

    python tools/test_setup/balance_run.py 5
    python tools/test_setup/balance_run.py 100 --class Wizard

Builds test003 as the reference player the monster model is tuned against (level-appropriate
gear rolled from the real drop tables, a tier-appropriate companion at your level), starts the
server, and logs a single client in.

To fight a specific monster:

    /spawnmonster <Species> <level>

USE A SPECIES THAT ACTUALLY SPAWNS AT THAT LEVEL. On launch this script prints the real spawn
table for your level — pick from it. An earlier playtest used `/spawnmonster Orc 50`; an Orc is
tier 2 with a 0% spawn rate at L50, so the entire test measured a monster no player meets there.
The same mistake had already been found and fixed inside the simulator, then reproduced by hand.

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

TEST_PLAN = """
================ WHAT TO CHECK THIS SESSION (2026-09-03) ================
Every damage ability moved onto the anchored model, the monster curve was re-calibrated
against it, and the combat cards now print numbers the SERVER computed. None of it has been
played. Ordered so a failure early makes the later ones unnecessary.

1. DO THE CARDS TELL THE TRUTH NOW?                    [the whole point of this session]
   Hover / read a card's damage number, play it, compare to the damage in the log.
   PASS = they match (within the normal damage variance).
   These four were the worst offenders you found, with what they USED to do:
     Field / Forcefield  said 252, granted 28   -> should now match your shield
     Meteor              said 554, dealt 264    -> should now match
     Magic Bolt          said ~20, dealt 200+   -> should now match
     Devastate           flat number, no mention of Momentum
   FAIL = any card still off by more than ~20%. Tell me which card and both numbers.

2. DEVASTATE SHOULD GROW VISIBLY WITH MOMENTUM         [Warrior only]
   Play Warrior cards to build Momentum and WATCH the Devastate card between each one.
   Its number should climb every time, and the card should say "Momentum N/5".
   At 1 Momentum it is deliberately feeble. At 5 with a full stamina bar it should be the
   biggest hit you can throw. PASS = the number moves as Momentum moves.

3. POST-COMBAT HP IS HONEST                            [3 previous fixes all looked right]
   Win a fight, let every animation finish, read your HP. Then move a step, or press space
   to rest, and read it again.
   FAIL = the number changes after you act. This is the one I most want confirmed, because
   the cause was found this time (five code paths threw the held HP away instead of applying
   it) but the symptom is timing-dependent. Spamming attack through the victory card and
   then immediately walking is the setup that showed it most reliably.

4. CAN A WARRIOR AND A TRICKSTER ACTUALLY KILL THINGS? [you died to gnolls on four characters]
   Fight 3-4 same-level monsters from the spawn table above, each starting at full HP.
   Expect roughly 5-6 turns and around half your health bar per fight.
   Before this pass a gearless Trickster needed 11.5 turns to kill what killed it in 8 - it
   could not win a straight fight at all. FAIL = still cannot close a normal fight.

5. OUTSMART ASKS BEFORE IT SPENDS                      [Trickster; it used to take 60% silently]
   Press Outsmart on the action bar. A prompt should open asking how much ENERGY to commit,
   pre-filled with the old automatic amount so Enter reproduces the old behaviour.
   Committing 0 is legal. PASS = you are asked, and the number you type is what is spent.

6. READ NOW GOES TO 8, AND EVERY STACK SHOULD PAY      [your proposal]
   Play Trickster cards and watch the Outsmart odds climb. It reads "Read N/8" now.
   Eight stacks reach the same ceiling five used to, so each step is smaller.
   FAIL = the odds stop moving before 8 (that was the original bug: stacks 3-5 did nothing).

7. PHANTOM STRIKE SHOULD SAY CRITICAL                  [it always did the damage, never said so]
   Play Phantom Strike, then attack. The log should call it a critical hit.

8. APEX SPECIES SHOULD BE TAGGED                       [shipped in v0.9.741, never seen]
   If you meet a Skeleton, Mimic, Wyvern, Wraith, Chimaera, Hydra or Phoenix, its health bar
   should read a red "TOMBSTONE  <name> [APEX]". Those are tuned harder on purpose and pay
   2x XP / 3x drops. /spawnmonster Skeleton <level> if none show up.

NOT worth testing: fight LENGTH at high level, and elite/boss win rates - both known-wrong
and already on the backlog. Boss danger is ~80% of your bar BY DESIGN and your call.
=========================================================================
"""

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
                      "--resolution", "1280x720", "server/server.tscn", "--playtest-log"],
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
    print("    /spawnmonster <Species> %d" % args.level)

    # Print the REAL spawn table for this level rather than a hardcoded hint that goes stale.
    # `Orc` is tier 2 with a 0% spawn rate by L50, so testing against one measures a creature
    # stretched far above its home tier. That produced a false "the game trivializes at high
    # level" result in the simulator, and was then reproduced by hand in a playtest.
    try:
        out = subprocess.run(
            [GODOT, "--headless", "--path", PROJECT,
             "--script", "res://tools/probe/spawn_species.gd", "--", str(args.level)],
            capture_output=True, text=True, timeout=120).stdout
        for line in out.splitlines():
            if line.startswith("Species actually") or line.startswith("   "):
                print("  " + line.strip() if line.startswith("Species") else line)
    except Exception as exc:
        print("  (could not read the spawn table: %s)" % exc)

    print(TEST_PLAN)

    return 0


if __name__ == "__main__":
    sys.exit(main())
