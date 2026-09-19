"""WHICH OPEN BACKLOG ITEMS ARE ACTUALLY ALREADY DONE?

⚑ OWNER, 2026-09-19, after being offered three items that were already built: *"You need to view
what we've already worked on over the last few sessions/days and update the backlog since it still
has stale information despite me asking a dozen times for it to be updated as we complete these
things."*

A dozen asks is not a memory problem, it is a missing check. CLAUDE.md already says the rule and
already says why rules without checks fail: *"A check nobody runs is not a check."* The backlog is
the single ordered to-do list, work is chosen off it, and nothing has ever verified that an open
line is still true.

WHAT IT DOES. For every `- [ ]` line it looks for EVIDENCE the work exists:

  * a probe named in the item (`tools/probe/x.gd`) that is present on disk
  * a function, constant or file the item names, present in the codebase
  * the item's own words claiming completion ("DONE", "SHIPPED", "✅") while still unticked

None of these prove an item is finished — an item can name a probe it wants written. So this
NEVER edits the backlog. It prints a ranked list of lines worth re-reading, and a human decides.
An audit that silently ticked things off would be a worse failure than the one it fixes.

⛑ IT ALSO FINDS DUPLICATES, which is the other half of the same disease and the one CLAUDE.md
calls out by name: *"the Dungeon Atlas was once tracked as three separate tasks in three separate
places."*

USAGE
    python tools/backlog_audit.py
    python tools/backlog_audit.py --quiet    # only the strong suspicions
"""
import os
import re
import sys
import subprocess

# ⛑ Windows consoles default to cp1252 and this file prints backlog titles verbatim, which
# carry the project's own ⛑ / ⚡ markers. Without this the audit dies on its first finding -
# which is the one failure mode an audit cannot have.
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BACKLOG = os.path.join(ROOT, "docs", "BACKLOG.md")

# Words an item uses about ITSELF when the work landed. An unticked line saying "DONE" is the
# cheapest possible catch and the most embarrassing to miss.
DONE_WORDS = re.compile(r"\b(DONE|SHIPPED|COMPLETE|✅|already (built|exists|shipped))\b", re.I)
PROBE = re.compile(r"`?(tools/probe/[a-z0-9_]+\.gd)`?")
SYMBOL = re.compile(r"`([A-Za-z_][A-Za-z0-9_]{4,})`")


def open_items(text):
    """Every unticked item, with its line number and full body (continuation lines included)."""
    lines = text.split("\n")
    out = []
    i = 0
    while i < len(lines):
        m = re.match(r"^(\s*)- \[ \] (.*)$", lines[i])
        if not m:
            i += 1
            continue
        indent, first = m.group(1), m.group(2)
        body = [first]
        j = i + 1
        while j < len(lines):
            nxt = lines[j]
            if re.match(r"^\s*- \[[ x~→]\]", nxt) or nxt.startswith("#"):
                break
            if nxt.strip() == "" and (j + 1 >= len(lines) or not lines[j + 1].startswith(indent + "  ")):
                break
            body.append(nxt)
            j += 1
        out.append({"line": i + 1, "title": re.sub(r"\*\*", "", first)[:88], "body": "\n".join(body)})
        i = j
    return out


def repo_has(sym):
    """Is this symbol defined anywhere in the game's own code?"""
    try:
        r = subprocess.run(["git", "grep", "-l", "-F", sym, "--", "*.gd", "*.py"],
                           cwd=ROOT, capture_output=True, timeout=25)
        return r.returncode == 0 and bool(r.stdout.strip())
    except Exception:
        return False


def main():
    quiet = "--quiet" in sys.argv
    text = open(BACKLOG, encoding="utf-8").read()
    items = open_items(text)

    strong, weak = [], []
    for it in items:
        reasons = []
        if DONE_WORDS.search(it["body"]):
            reasons.append(("STRONG", "its own text says the work is done"))
        for pr in set(PROBE.findall(it["body"])):
            if os.path.exists(os.path.join(ROOT, pr)):
                reasons.append(("STRONG", "the probe it names EXISTS: %s" % pr))
        if not reasons:
            syms = [s for s in set(SYMBOL.findall(it["body"]))
                    if "_" in s and not s.startswith("tools/")][:4]
            found = [s for s in syms if repo_has(s)]
            if found and len(found) == len(syms) and syms:
                reasons.append(("weak", "every symbol it names exists: %s" % ", ".join(found)))
        if reasons:
            (strong if any(r[0] == "STRONG" for r in reasons) else weak).append((it, reasons))

    print("")
    print("===== OPEN ITEMS THAT LOOK ALREADY DONE =====")
    print("  %d open items; %d strong suspicion(s), %d weak" % (len(items), len(strong), len(weak)))
    print("  Nothing here is edited automatically - these are lines to RE-READ.")
    for it, reasons in strong:
        print("")
        print("  BACKLOG.md:%-6d %s" % (it["line"], it["title"]))
        for _, why in reasons:
            print("      - %s" % why)
    if not quiet:
        for it, reasons in weak:
            print("")
            print("  (weak) BACKLOG.md:%-6d %s" % (it["line"], it["title"]))
            for _, why in reasons:
                print("      - %s" % why)

    # ⚡ THE BLIND SPOT, NAMED. Measured 2026-09-19 by injecting one stale item of each shape:
    #
    #     own text says DONE        -> caught
    #     names an existing probe   -> caught
    #     names existing symbols    -> caught (weak)
    #     PROSE ONLY, no evidence   -> NOT CAUGHT
    #
    # The last shape is exactly what cost the owner time: "tools are a pain, you cannot see
    # backups" names nothing checkable, and `_auto_equip_tool_replacement` had existed for ages.
    # Same for dungeon slice 4. A checker that is silent about what it cannot check is worse than
    # one that admits it, because silence reads as "still open" - so the unverifiable items are
    # listed. These are the ones a human MUST check in the code before proposing them.
    print("")
    print("===== ITEMS THIS AUDIT CANNOT VERIFY - CHECK THESE BY HAND =====")
    unauditable = []
    for it in items:
        body = it["body"]
        if DONE_WORDS.search(body):
            continue
        if PROBE.findall(body):
            continue
        if [x for x in set(SYMBOL.findall(body)) if "_" in x]:
            continue
        unauditable.append(it)
    print("  %d of %d open items name NO probe, symbol or completion word." % (len(unauditable), len(items)))
    print("  The audit is BLIND to these. Grep the code for the capability before proposing one.")
    for it in unauditable:
        print("      BACKLOG.md:%-6d %s" % (it["line"], it["title"]))

    # ⛑ DUPLICATES. CLAUDE.md: "the Dungeon Atlas was once tracked as three separate tasks in
    # three separate places." Two lines opening with the same words are the cheapest tell.
    print("")
    print("===== THE SAME ITEM LISTED TWICE =====")
    seen = {}
    for it in items:
        key = re.sub(r"[^a-z ]", "", it["title"].lower()).strip()[:38]
        if len(key) < 12:
            continue
        seen.setdefault(key, []).append(it)
    dupes = {k: v for k, v in seen.items() if len(v) > 1}
    if not dupes:
        print("  none found")
    for k, v in dupes.items():
        print("  '%s...'" % k)
        for it in v:
            print("      BACKLOG.md:%d" % it["line"])

    print("")
    print("  Run this BEFORE proposing what to work on, not after.")
    print("")
    return 0


if __name__ == "__main__":
    sys.exit(main())
