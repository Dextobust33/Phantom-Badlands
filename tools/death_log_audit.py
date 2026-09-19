"""WHAT IS ACTUALLY KILLING LIVE PLAYERS, read off the server's own death log.

Owner 2026-09-18, redirecting a balance pass that had started with the simulator: *"I'm not
worried about the wizard thing that seems like a remnant. I would just go off of the data from
newer players."* and then *"when you mentioned live population i meant live server players
including deaths, don't forget the deaths as there is plenty of data you can get from those logs
as well."*

\u26d1 THIS IS BETTER EVIDENCE THAN THE SIMULATOR AND IT WAS SITTING THERE. The chain measures a
REFERENCE player against a modelled encounter; this is every real death that has actually
happened, with the monster, the level gap, the rounds it lasted and how much of its own bar the
character had left when the fight started. CLAUDE.md's rule is to check the instrument before
doubting the player - the death log needs no instrument at all.

WHAT IT REPORTS, and why each one is a balance question:
  * deaths BY LEVEL BAND      - where the curve actually bites, against where players actually are
  * deaths BY CLASS           - the per-class gap the chain is structurally unable to fix
  * the LEVEL GAP             - was it an over-levelled monster, or something at your own level?
    A death to something 40 levels up is a player decision; a death at parity is the curve.
  * ROUNDS FOUGHT             - a one-round death is a different problem from a nine-round loss
  * HP AT START               - did they walk in wounded? That is attrition, not encounter power.

USAGE
    python tools/death_log_audit.py           # live server
"""
import json
import subprocess
import sys
import collections

# The same guard `tools/backlog_audit.py` carries, and for a reason this script states in its own
# docstring: it prints player-authored names and monster variants, and Windows consoles default to
# cp1252. It decoded the SSH pipe as UTF-8 from the start but never fixed its own stdout, so any
# non-ASCII character reaching a print - a player name, or the warning marker added 2026-09-19 -
# killed the run mid-report. An audit that dies on its first interesting finding is worse than one
# that never runs, because it looks like a crash rather than a result.
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

SSH_KEY = "/c/Users/Dexto/Desktop/PhantomBadlandsSSH/ssh-key-2026-04-21.key"
SERVER = "ubuntu@5.78.217.135"
PATH = "/home/ubuntu/.local/share/godot/app_userdata/PhantomBadlands/data/leaderboard.json"

# The 2026-09-05 early-game pass. A death before it happened under different rules and is not
# evidence about the current ones - same split `check_player_progress.sh` makes for characters.
CUTOFF = 1788480000


def band(lvl):
    if lvl <= 9:
        return "1-9"
    if lvl <= 24:
        return "10-24"
    if lvl <= 49:
        return "25-49"
    if lvl <= 99:
        return "50-99"
    return "100+"


def no_detail(e):
    """Was this death's FIGHT actually recorded, or is the record empty?

    (2026-09-19) Every field in a death record defaults to 0, so a death written with no
    combat data at all is byte-identical to a character who entered at 0 HP, fought zero
    rounds and dealt nothing. Both PARTY death paths passed no combat data, so 7 of 50 live
    deaths were blanks - and this audit printed them in section 3 as `rounds 0.0 started 0%`,
    under the heading "these are the curve's, not the player's". A fifth of the strongest
    evidence that the early game is too hard was a missing function argument.

    The server now stamps `has_combat_detail`. Records written before that lack the flag, so
    the legacy tell is the one that produced the bug: EVERY field zero at once. A real fight
    cannot have zero rounds and zero HP-at-start and zero damage in both directions.
    """
    dd = e.get("death_data", {})
    if "has_combat_detail" in dd:
        return not dd.get("has_combat_detail")
    return (int(dd.get("rounds_fought", 0) or 0) == 0
            and float(dd.get("player_hp_at_start", 0) or 0) == 0
            and float(dd.get("total_damage_dealt", 0) or 0) == 0
            and float(dd.get("total_damage_taken", 0) or 0) == 0)


BANDS = ["1-9", "10-24", "25-49", "50-99", "100+"]


def main():
    # ⛑ BYTES, NOT text=True. The log carries player-authored names and monster variants with
    # non-ASCII characters, and Python on Windows decodes a pipe as cp1252 by default - the first
    # run died on byte 0x9d and handed `json.loads` a None. Decode explicitly as UTF-8.
    raw = subprocess.run(["ssh", "-o", "ConnectTimeout=20", "-i", SSH_KEY, SERVER, "cat %s" % PATH],
                         capture_output=True)
    if raw.returncode != 0:
        print("could not read the live death log:")
        print(raw.stderr.decode("utf-8", "replace")[:400])
        return 1
    entries = json.loads(raw.stdout.decode("utf-8", "replace")).get("entries", [])
    cur = [e for e in entries if int(e.get("died_at", 0)) >= CUTOFF]
    old = len(entries) - len(cur)

    print("")
    print("===== LIVE DEATHS =====")
    print("  %d recorded; %d since the 2026-09-05 balance pass, %d before it (not evidence)"
          % (len(entries), len(cur), old))
    if not cur:
        print("  nothing since the cutoff - no current-era evidence yet.")
        return 0

    print("")
    print("===== 1. WHERE THE CURVE ACTUALLY BITES =====")
    by_band = collections.Counter(band(int(e.get("level", 1))) for e in cur)
    print("  %-8s %-7s %s" % ("band", "deaths", ""))
    for b in BANDS:
        n = by_band.get(b, 0)
        if n:
            print("  %-8s %-7d %s" % (b, n, "#" * n))

    print("")
    print("===== 2. BY CLASS - the gap a chain run cannot close =====")
    by_cls = collections.Counter(str(e.get("class", "?")) for e in cur)
    for c, n in by_cls.most_common():
        print("  %-12s %-4d %s" % (c, n, "#" * n))

    print("")
    print("===== 3. WAS IT OVER-LEVELLED, OR THE CURVE? =====")
    # \u26d1 THE QUESTION THAT DECIDES WHETHER THIS IS A BALANCE PROBLEM AT ALL. Dying to something
    # 40 levels above you is a decision you made. Dying to something at your own level is the curve.
    gaps = []
    for e in cur:
        lvl = int(e.get("level", 1))
        cause = str(e.get("cause_of_death", ""))
        ml = None
        if "(Lvl " in cause:
            try:
                ml = int(cause.split("(Lvl ")[1].split(")")[0])
            except Exception:
                ml = None
        if ml is not None:
            gaps.append((lvl, ml, ml - lvl, cause.split(" (Lvl")[0], e))
    # Blanks are still DEATHS - they are counted everywhere a death is counted - but they are
    # not EVIDENCE about the curve, because nothing about the fight was recorded.
    blanks = [g for g in gaps if no_detail(g[4])]
    gaps = [g for g in gaps if not no_detail(g[4])]
    at_parity = [g for g in gaps if g[2] <= 2]
    modest = [g for g in gaps if 2 < g[2] <= 10]
    far = [g for g in gaps if g[2] > 10]
    print("  %d of %d deaths name the monster's level" % (len(gaps), len(cur)))
    print("    at or below the player's level (gap <= 2) ... %d" % len(at_parity))
    print("    modestly above (3-10) ..................... %d" % len(modest))
    print("    far above (11+) ........................... %d" % len(far))
    print("")
    if blanks:
        print("")
        print("  ⚠ %d of these have NO fight recorded and are EXCLUDED from the list below."
              % len(blanks))
        print("    They are real deaths, but nothing about the fight was written, so they say")
        print("    nothing about the curve. Left in, each reads as a one-shot at parity.")
    print("")
    print("  AT PARITY - these are the curve's, not the player's:")
    for lvl, ml, gap, name, e in sorted(at_parity, key=lambda g: g[0])[:14]:
        dd = e.get("death_data", {})
        print("    L%-5d vs %-26s Lv%-5d  %s  rounds %-3s  started %s%%"
              % (lvl, name[:26], ml, str(e.get("class", "?"))[:9].ljust(9),
                 str(dd.get("rounds_fought", "?")),
                 _pct(dd.get("player_hp_at_start"), dd.get("player_max_hp"))))

    print("")
    print("===== 4. HOW THE DEATHS WENT =====")
    rounds = [int(e.get("death_data", {}).get("rounds_fought", 0)) for e in cur
              if e.get("death_data", {}).get("rounds_fought") is not None]
    rounds = [r for r in rounds if r > 0]
    if rounds:
        rounds.sort()
        quick = len([r for r in rounds if r <= 2])
        print("  rounds fought: median %d, shortest %d, longest %d" % (
            rounds[len(rounds) // 2], rounds[0], rounds[-1]))
        print("  died in 2 rounds or fewer: %d of %d (%.0f%%)" % (
            quick, len(rounds), 100.0 * quick / len(rounds)))
    # Walked in wounded? That is attrition, not encounter power - a different fix entirely.
    wounded = 0
    counted = 0
    for e in cur:
        dd = e.get("death_data", {})
        st, mx = dd.get("player_hp_at_start"), dd.get("player_max_hp")
        if st is None or not mx:
            continue
        counted += 1
        if float(st) / float(mx) < 0.7:
            wounded += 1
    if counted:
        print("  walked in below 70%% HP: %d of %d (%.0f%%)  - attrition, not encounter power"
              % (wounded, counted, 100.0 * wounded / counted))

    print("")
    print("===== 4b. THE ZERO-ROUND DEATHS =====")
    # ⛑ SEVERAL ENTRIES READ `rounds 0, started 0%`. A death with no rounds and no starting HP
    # is not a fight the player lost - it is something else, and lumping it in with encounter
    # balance would mis-size the whole curve. Named separately so it is investigated rather than
    # averaged away.
    zero = [e for e in cur
            if int(e.get("death_data", {}).get("rounds_fought", -1) or 0) == 0]
    print("  %d of %d deaths record ZERO rounds fought" % (len(zero), len(cur)))
    for e in zero[:10]:
        dd = e.get("death_data", {})
        print("    L%-4s %-10s vs %-24s  start %s/%s HP, dealt %s, taken %s"
              % (e.get("level", "?"), str(e.get("class", "?"))[:10],
                 str(e.get("cause_of_death", "?"))[:24],
                 dd.get("player_hp_at_start", "?"), dd.get("player_max_hp", "?"),
                 dd.get("total_damage_dealt", "?"), dd.get("total_damage_taken", "?")))

    print("")
    print("===== 4c. ONE-SHOT? how much of the bar the killing blow took =====")
    # A death in one or two rounds is only a balance fault if the player could not have acted.
    one_hit = 0
    counted2 = 0
    for e in cur:
        dd = e.get("death_data", {})
        mx = dd.get("player_max_hp")
        taken = dd.get("total_damage_taken")
        rounds = dd.get("rounds_fought")
        if not mx or taken is None or not rounds or int(rounds) < 1:
            continue
        counted2 += 1
        if int(rounds) <= 2 and float(taken) >= float(mx):
            one_hit += 1
    if counted2:
        print("  died in <=2 rounds having taken a FULL BAR or more: %d of %d (%.0f%%)"
              % (one_hit, counted2, 100.0 * one_hit / counted2))
        print("  that is the shape that reads as 'I never got to play' - decisions, not length")

    print("")
    print("===== 5. WHAT KILLS MOST OFTEN =====")
    killers = collections.Counter(
        str(e.get("cause_of_death", "?")).split(" (Lvl")[0] for e in cur)
    for k, n in killers.most_common(12):
        print("  %-34s %d" % (k[:34], n))
    print("")
    return 0


def _pct(a, b):
    if a is None or not b:
        return "?"
    return str(int(round(100.0 * float(a) / float(b))))


if __name__ == "__main__":
    sys.exit(main())
