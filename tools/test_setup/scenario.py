#!/usr/bin/env python3
"""Put the test characters into a known state before a 2-client test run.

Testing co-op by hand is slow: sign in twice, party up, walk somewhere dangerous, then try to
engineer the exact situation (someone about to die, someone out of mana...). This writes the
save files directly so the characters are ALREADY in that state when you log in.

    python tools/test_setup/scenario.py <scenario>
    python tools/test_setup/scenario.py --list

THE SERVER MUST BE STOPPED while this runs — it holds characters in memory and saves over
whatever is on disk. The script refuses to run if port 9080 is listening.
"""
import json, os, sys, subprocess

SAVE_DIR = os.path.expandvars(r"%APPDATA%\Godot\app_userdata\PhantomBadlands\data\characters")
CHARS = {"test02": "acc_4_test02.json", "test002": "acc_5_test002.json"}

# Permadeath DELETES the character, so a death test destroys its own fixture. Rather than make
# you rebuild one by hand every time, missing test characters are recreated automatically
# through the real Character + persistence code (identical to one made in-game).
RECREATE = {
    "test02":  dict(acc="acc_4", cls="Wizard",   race="Halfling", level=12, stat="intelligence"),
    "test002": dict(acc="acc_5", cls="Sorcerer", race="Dwarf",    level=9,  stat="intelligence"),
}
GODOT = r"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
PROJECT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def ensure_character(cname):
    """Recreate a test character if permadeath removed it."""
    path = os.path.join(SAVE_DIR, CHARS[cname])
    if os.path.exists(path):
        return
    spec = RECREATE[cname]
    print("  %s is gone (permadeath?) — recreating" % cname)
    subprocess.run([GODOT, "--headless", "--path", PROJECT, "--script",
                    "tools/test_setup/make_char.gd", "--",
                    "--acc=%s" % spec["acc"], "--name=%s" % cname, "--class=%s" % spec["cls"],
                    "--race=%s" % spec["race"], "--level=%d" % spec["level"],
                    "--stat=%s" % spec["stat"]], capture_output=True, text=True, timeout=180)
    # Register the character on the account. persistence.add_character_to_account needs its
    # accounts_data loaded, which the headless node's lifecycle does not reliably reach — the
    # character file got written but the account slot stayed empty, so the client saw an empty
    # character list and sat on the select screen. Doing it here is deterministic.
    acc_path = os.path.join(os.path.dirname(SAVE_DIR), "accounts.json")
    with open(acc_path, encoding="utf-8") as f:
        db = json.load(f)
    slots = db["accounts"][spec["acc"]].setdefault("character_slots", [])
    if cname not in slots:
        slots.append(cname)
        with open(acc_path, "w", encoding="utf-8") as f:
            json.dump(db, f, indent="	")
        print("  registered %s on %s" % (cname, spec["acc"]))

def potion(tier=1, qty=5):
    return {"name": "Health Potion", "type": "health_potion", "item_type": "health_potion",
            "is_consumable": True, "quantity": qty, "tier": tier, "level": 1, "value": 25}

SCENARIOS = {
    "party_death": {
        "doc": "Both members one hit from death, standing together. For testing what the "
               "survivors see when someone falls mid-fight.",
        "apply": lambda c: c.update({"current_hp": 3}),
    },
    "near_death_one": {
        "doc": "Only test002 is nearly dead; test02 is healthy. Tests a single member falling "
               "while the fight continues.",
        "apply": lambda c: c.update({"current_hp": 3}) if c["name"] == "test002" else None,
    },
    "healthy": {
        "doc": "Both at full HP — reset after a death test.",
        "apply": lambda c: c.update({"current_hp": c.get("max_hp", 100)}),
    },
    "party_wipe": {
        "doc": "Both members at 1 HP — the whole party should die. Tests permadeath for every "
               "member at once, and what the client does when nobody survives.",
        "apply": lambda c: c.update({"current_hp": 1}),
    },
    "stocked": {
        "doc": "Give both members a stack of potions (for the item-use rules).",
        "apply": lambda c: c["inventory"].append(potion()),
    },
}

def server_running():
    try:
        out = subprocess.run(["netstat", "-an"], capture_output=True, text=True, timeout=10).stdout
        return any("0.0.0.0:9080" in l and "LISTENING" in l for l in out.splitlines())
    except Exception:
        return False

def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("--list", "-l", "-h", "--help"):
        print("scenarios:")
        for k, v in SCENARIOS.items():
            print("  %-16s %s" % (k, v["doc"]))
        return 0
    name = sys.argv[1]
    if name not in SCENARIOS:
        print("unknown scenario %r (use --list)" % name)
        return 1
    if server_running():
        print("REFUSING: the server is running on 9080. Stop it first — it would save over these edits.")
        return 1

    # Park them side by side so they can party up without walking.
    for cname in CHARS:
        ensure_character(cname)

    anchor = None
    for i, (cname, fn) in enumerate(CHARS.items()):
        path = os.path.join(SAVE_DIR, fn)
        with open(path, encoding="utf-8") as f:
            c = json.load(f)
        if anchor is None:
            anchor = (c.get("x", 0), c.get("y", 0))
        else:
            c["x"], c["y"] = anchor[0] + 1, anchor[1]
        c["in_combat"] = False          # never leave a stale lockout behind
        c["saved_combat_state"] = {}
        SCENARIOS[name]["apply"](c)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(c, f, indent="\t")
        print("  %-8s hp=%-5s at (%s, %s)" % (cname, c.get("current_hp"), c.get("x"), c.get("y")))
    print("scenario %r applied. Start the server, then the clients." % name)
    return 0

if __name__ == "__main__":
    sys.exit(main())
