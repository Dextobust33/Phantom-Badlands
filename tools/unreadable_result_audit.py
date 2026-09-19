"""WHICH RESULTS DOES THE SERVER ERASE BEFORE THE PLAYER CAN READ THEM?

⚑ OWNER, LIVE, 2026-09-19: *"I just looted a corpse on the live server but I don't see what I got
from it in the right column anywhere."* The loot page was drawn and then wiped, because
`handle_loot_corpse` sends `corpse_looted` and then immediately calls `send_character_update` and
`send_location_update` — which arrive microseconds later and redraw over it.

CLAUDE.md has carried this rule since long before that report:

    "Server messages (character_update, location, text, combat_update, inventory_update)
     frequently trigger UI refreshes that call display_xxx() and wipe game_output, clearing any
     result message the player was trying to read. The classic symptom: player sees the result
     for a split second, then it's gone."

**A check nobody runs is not a check.** The rule was written, the checklist was written, and the
corpse loot screen shipped without it anyway — because nothing ever looked.

WHAT IT DOES. It works from the CAUSE, which lives on the server, not from the client:

    1. find every server function that calls `send_to_peer(..., "type": "X", ...)` AND also
       calls a redraw-triggering send in the same function (character_update / location /
       inventory_update). That pairing is precisely the hazard the rule describes.
    2. for each such message type, look at the CLIENT's handler for it.
    3. report any whose handler draws a page (`display_game`) but never sets `pending_continue`,
       which is the only flag the redraw paths actually stand down for.

⛑ WHY `pending_continue` AND NOT SOMETHING CHEAPER. It is what `_ow_heal_canvas`, the location
pass and the event redraws all check before painting. A page without it is not protected by
anything, whatever else it does.

⚡ ITS BLIND SPOT, NAMED. A handler can legitimately draw something transient that is MEANT to be
replaced (a toast, a status line). This cannot tell that from a result the player needed. So it
prints findings to be READ, never edits anything, and a reviewed-and-fine entry goes in
`ACCEPTED` below with the reason — same discipline as `backlog_audit.py`'s `audited:` marker.

USAGE
    python tools/unreadable_result_audit.py
"""
import io
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Messages whose arrival makes the client redraw and wipe whatever page was up.
REDRAW_SENDS = ["send_character_update", "send_location_update", "send_inventory_update"]

# Reviewed by hand and genuinely fine: the message is transient by design, or the client
# protects it some other proven way. Reason required — an empty entry is not an exemption.
ACCEPTED = {
    "toast": "transient by design; it floats over the canvas and is meant to expire",
    "error": "a one-line error, not a page; it does not clear the canvas",
    "text": "the generic text channel - used for chat and one-liners, not result pages",
}


def server_message_hazards(src):
    """{message_type: function_name} for every type sent alongside a redraw-triggering send."""
    out = {}
    funcs = [(m.start(), m.group(1)) for m in re.finditer(r"\nfunc ([A-Za-z_][A-Za-z0-9_]*)\(", src)]
    for idx, (pos, name) in enumerate(funcs):
        end = funcs[idx + 1][0] if idx + 1 < len(funcs) else len(src)
        body = src[pos:end]
        if not any(r in body for r in REDRAW_SENDS):
            continue
        # The types this function sends. Only `send_to_peer` — a broadcast is not this player's
        # page, and counting it would flood the report with other people's notifications.
        for m in re.finditer(r'send_to_peer\([^)]*?"type"\s*:\s*"([a-z_]+)"', body, re.S):
            out.setdefault(m.group(1), name)
    return out


def client_handlers(src):
    """{message_type: body} for the client's message-type match cases."""
    lines = src.split("\n")
    cases = []
    for i, l in enumerate(lines):
        m = re.match(r'^\t\t"([a-z_]+)":\s*$', l)
        if m:
            cases.append((i, m.group(1)))
    out = {}
    for idx, (i, name) in enumerate(cases):
        end = cases[idx + 1][0] if idx + 1 < len(cases) else len(lines)
        # Keep the FIRST occurrence: client.gd has match cases in other functions that reuse
        # these names, and the message handler is the one that matters here.
        out.setdefault(name, (i + 1, "\n".join(lines[i:end])))
    return out


def main():
    srv = io.open(os.path.join(ROOT, "server", "server.gd"), encoding="utf-8").read()
    cli = io.open(os.path.join(ROOT, "client", "client.gd"), encoding="utf-8").read()

    hazards = server_message_hazards(srv)
    handlers = client_handlers(cli)

    findings = []
    accepted = []
    unhandled = []
    for mtype, fn in sorted(hazards.items()):
        if mtype not in handlers:
            unhandled.append((mtype, fn))
            continue
        line, body = handlers[mtype]
        if "display_game(" not in body:
            continue          # not a page - nothing to protect
        if "pending_continue = true" in body:
            continue          # protected
        if mtype in ACCEPTED:
            accepted.append((mtype, fn, ACCEPTED[mtype]))
            continue
        findings.append((mtype, fn, line))

    print("")
    print("===== RESULTS THE SERVER MAY ERASE BEFORE THEY ARE READ =====")
    print("  %d message types are sent from a function that ALSO triggers a redraw." % len(hazards))
    print("  Listed below: those whose client handler draws a page and never protects it.")
    print("")
    if not findings:
        print("  none - every result page sent alongside a redraw claims pending_continue")
    for mtype, fn, line in findings:
        print("  %-24s server.gd::%s" % (mtype, fn))
        print("  %-24s client.gd:%d draws a page, never sets pending_continue" % ("", line))
        print("")

    if accepted:
        print("===== REVIEWED AND ACCEPTED =====")
        for mtype, fn, why in accepted:
            print("  %-24s %s" % (mtype, why))
        print("")

    if unhandled:
        print("===== SENT BUT NO CLIENT HANDLER FOUND (check by hand) =====")
        print("  The audit could not locate a match case for these, so it says nothing about them.")
        for mtype, fn in unhandled[:20]:
            print("  %-24s server.gd::%s" % (mtype, fn))
        print("")

    print("  Findings are lines to RE-READ, not bugs. A transient page is allowed to be")
    print("  replaced; add it to ACCEPTED with a reason once you have decided that.")
    print("")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
