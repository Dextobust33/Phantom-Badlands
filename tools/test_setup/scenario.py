#!/usr/bin/env python3
"""Put the test characters into a known state before a test run.

Testing by hand is slow: sign in two or three times, party up, walk somewhere the thing you are
testing actually exists, then try to engineer the exact situation. This writes the save files
directly so the characters are ALREADY in that state when they log in.

    python tools/test_setup/scenario.py <scenario>
    python tools/test_setup/scenario.py --list

THE SERVER MUST BE STOPPED while this runs - it holds characters in memory and saves over
whatever is on disk. The script refuses to run if port 9080 is listening.
"""
import json
import os
import subprocess
import sys

GODOT = r"D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
PROJECT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SAVE_DIR = os.path.expandvars(r"%APPDATA%\Godot\app_userdata\PhantomBadlands\data\characters")
ACCOUNTS = os.path.join(os.path.dirname(SAVE_DIR), "accounts.json")

# account username -> (account id, character name, save file)
PLAYERS = [
    ("Testing",  "acc_4", "test02",  "acc_4_test02.json"),
    ("Testing2", "acc_5", "test002", "acc_5_test002.json"),
    ("Testing3", "acc_6", "test003", "acc_6_test003.json"),
    ("Testing4", "acc_7", "test004", "acc_7_test004.json"),
    ("Testing5", "acc_8", "test005", "acc_8_test005.json"),
]

# Permadeath DELETES the character, so a death test destroys its own fixture. Missing test
# characters (and accounts) are recreated automatically through the real Character +
# persistence code, so the result is identical to one made in-game.
RECREATE = {
    "test02":  dict(cls="Wizard",   race="Halfling", level=12, stat="intelligence"),
    "test002": dict(cls="Sorcerer", race="Dwarf",    level=9,  stat="intelligence"),
    "test003": dict(cls="Fighter",  race="Orc",      level=10, stat="strength"),
    "test004": dict(cls="Ranger",   race="Elf",      level=10, stat="dexterity"),
    "test005": dict(cls="Paladin",  race="Ogre",     level=10, stat="strength"),
}

# Real coordinates for the live world seed, found with find_tile.gd. Re-run it if the world
# seed ever changes - terrain generated with the wrong seed does NOT match the live server.
# Default anchor for every scenario that does not pin its own. A RECREATED character spawns at
# the Crossroads (0,0), which is a SAFE ZONE where nothing can be hunted - so any scenario that
# might involve a fight has to place the party deliberately. ~level 13 here.
DEFAULT_AT = (57, -11)

TILES = {
    "water":  (59, -10),
    "ore":    (57, -12),
    "forest": (56, -12),
}


def tool(subtype, name, tier=1):
    """A gathering tool shaped like drop_tables.generate_tool output."""
    return {
        "id": abs(hash(subtype)) % 100000, "name": name, "type": "tool", "subtype": subtype,
        "tier": tier, "durability": 20, "max_durability": 20, "rarity": "common",
        "max_saves": 0, "tool_bonuses": {"reveals": 1, "save": True},
    }


ALL_TOOLS = [
    tool("fishing_rod", "Bent Rod"),
    tool("pickaxe", "Chipped Pickaxe"),
    tool("axe", "Rusty Axe"),
    tool("sickle", "Worn Sickle"),
]


def give_tools(c):
    have = {str(i.get("subtype", "")) for i in c.get("inventory", []) if i.get("type") == "tool"}
    for t in ALL_TOOLS:
        if t["subtype"] not in have:
            c["inventory"].append(dict(t))


def give_materials(c):
    """Enough common materials that a craft can actually be attempted."""
    pouch = c.setdefault("crafting_materials", {})
    for mat in ("iron_ore", "oak_wood", "leather", "cloth", "stone"):
        pouch[mat] = int(pouch.get(mat, 0)) + 20


SCENARIOS = {
    "healthy": dict(
        doc="Everyone at full HP, standing together. The default sandbox.",
        players=2, apply=lambda c: c.update({"current_hp": c.get("max_hp", 100)})),

    "near_death_one": dict(
        doc="Only test002 is nearly dead; the others are healthy. A single member falls while "
            "the fight continues.",
        players=2,
        apply=lambda c: c.update({"current_hp": 3}) if c["name"] == "test002" else None),

    "party_wipe": dict(
        doc="Everyone at 1 HP AND parked in a level ~134 zone - the next hit wipes the party. "
            "1 HP near the starting posts was not reliably lethal (the monster can miss, or "
            "simply be killed first).",
        players=2, at=(250, -150),
        apply=lambda c: c.update({"current_hp": 1})),

    "deadly_zone": dict(
        doc="Healthy, parked in a level ~134 zone - for fights you are meant to lose, or for "
            "testing how far a party can actually push.",
        players=2, at=(250, -150),
        apply=lambda c: c.update({"current_hp": c.get("max_hp", 100)})),

    "party3": dict(
        doc="THREE members, healthy, together. The only way to exercise leadership TRANSFER "
            "and 3-way rotation - a 2-person party disbands instead of transferring.",
        players=3, apply=lambda c: c.update({"current_hp": c.get("max_hp", 100)})),

    "party3_deadly": dict(
        doc="THREE members at 1 HP in a level ~134 zone. The leader dies and the party should "
            "TRANSFER leadership rather than disband - the path a 2-person party cannot reach.",
        players=3, at=(250, -150),
        apply=lambda c: c.update({"current_hp": 1})),

    "party5": dict(
        doc="A FULL party of five (leader + four) - the max. Exercises the widest combat party "
            "column, the longest follower tail through a post doorway, and rotation across five.",
        players=5, apply=lambda c: c.update({"current_hp": c.get("max_hp", 100)})),

    "party3_leader_dies": dict(
        doc="THREE members in a NORMAL zone, but only the LEADER is at 1 HP. The leader dies "
            "while two healthy members remain, which is the only way to reach the leadership "
            "TRANSFER branch - in a lethal zone the others die first and the party drops to two, "
            "which disbands instead.",
        # Pinned OUTSIDE the safe zone: a recreated character spawns at the Crossroads (0,0)
        # where nothing can be hunted, so a scenario that relies on a fight must place them.
        # ~level 13 here: lethal to the 1 HP leader, survivable for the healthy two.
        players=3, at=(57, -11),
        apply=lambda c: c.update({"current_hp": 1 if c["name"] == "test02"
                                  else c.get("max_hp", 100)})),

    "gather_water": dict(
        doc="Party standing on water with rods - for fishing and the party reward share.",
        players=2, at=TILES["water"],
        apply=lambda c: (c.update({"current_hp": c.get("max_hp", 100)}), give_tools(c))),

    "gather_ore": dict(
        doc="Party at an ore vein with pickaxes - for mining and the party reward share.",
        players=2, at=TILES["ore"],
        apply=lambda c: (c.update({"current_hp": c.get("max_hp", 100)}), give_tools(c))),

    "gather_forest": dict(
        doc="Party in forest with axes - for chopping and the party reward share.",
        players=2, at=TILES["forest"],
        apply=lambda c: (c.update({"current_hp": c.get("max_hp", 100)}), give_tools(c))),

    "craft_ready": dict(
        doc="Party stocked with tools and 20 of each common material, ready to craft - for the "
            "crafting XP share (the crafted ITEM stays with the crafter).",
        players=2,
        apply=lambda c: (c.update({"current_hp": c.get("max_hp", 100)}), give_tools(c),
                         give_materials(c))),

    "stocked": dict(
        doc="Give everyone a stack of potions (for the combat item rules).",
        players=2,
        apply=lambda c: c["inventory"].append({
            "name": "Health Potion", "type": "health_potion", "item_type": "health_potion",
            "is_consumable": True, "quantity": 5, "tier": 1, "level": 1, "value": 25})),
}


def server_running():
    try:
        out = subprocess.run(["netstat", "-an"], capture_output=True, text=True, timeout=10).stdout
        return any("0.0.0.0:9080" in l and "LISTENING" in l for l in out.splitlines())
    except Exception:
        return False


def ensure_character(user, acc, cname, fn):
    """Recreate a test character (and its account) if permadeath removed it."""
    if os.path.exists(os.path.join(SAVE_DIR, fn)):
        return
    spec = RECREATE[cname]
    print("  %s is gone (permadeath?) - recreating" % cname)
    subprocess.run([GODOT, "--headless", "--path", PROJECT, "--script",
                    "tools/test_setup/make_char.gd", "--",
                    "--acc=%s" % acc, "--user=%s" % user, "--pass=devtest",
                    "--name=%s" % cname, "--class=%s" % spec["cls"], "--race=%s" % spec["race"],
                    "--level=%d" % spec["level"], "--stat=%s" % spec["stat"]],
                   capture_output=True, text=True, timeout=240)
    # Register on the account. add_character_to_account needs accounts_data loaded, which the
    # headless node's lifecycle does not reliably reach - the character file gets written but
    # the slot stays empty and the client sees an empty character list. Do it here instead.
    with open(ACCOUNTS, encoding="utf-8") as f:
        db = json.load(f)
    if acc in db.get("accounts", {}):
        slots = db["accounts"][acc].setdefault("character_slots", [])
        if cname not in slots:
            slots.append(cname)
            with open(ACCOUNTS, "w", encoding="utf-8") as f:
                json.dump(db, f, indent="\t")
            print("  registered %s on %s" % (cname, acc))


def players_for(name):
    return SCENARIOS[name].get("players", 2)


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("--list", "-l", "-h", "--help"):
        print("scenarios:")
        for k, v in SCENARIOS.items():
            print("  %-14s (%d players) %s" % (k, v.get("players", 2), v["doc"]))
        return 0
    name = sys.argv[1]
    if name not in SCENARIOS:
        print("unknown scenario %r (use --list)" % name)
        return 1
    if server_running():
        print("REFUSING: the server is running on 9080. Stop it first - it would save over these edits.")
        return 1

    spec = SCENARIOS[name]
    n = players_for(name)
    for user, acc, cname, fn in PLAYERS[:n]:
        ensure_character(user, acc, cname, fn)

    anchor = None
    for i, (user, acc, cname, fn) in enumerate(PLAYERS[:n]):
        path = os.path.join(SAVE_DIR, fn)
        with open(path, encoding="utf-8") as f:
            c = json.load(f)
        spot = spec.get("at", DEFAULT_AT)
        if anchor is None:
            anchor = spot if spot else (c.get("x", 0), c.get("y", 0))
            c["x"], c["y"] = anchor[0], anchor[1]
        else:
            # Stand them side by side so they can party up without walking.
            c["x"], c["y"] = anchor[0] + i, anchor[1]
        c["in_combat"] = False           # never leave a stale lockout behind
        c["saved_combat_state"] = {}
        spec["apply"](c)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(c, f, indent="\t")
        print("  %-8s hp=%-5s at (%s, %s)" % (cname, c.get("current_hp"), c.get("x"), c.get("y")))
    print("scenario %r applied for %d player(s)." % (name, n))
    return 0


if __name__ == "__main__":
    sys.exit(main())
